import {
  ProviderError,
  isRetryableStatus,
  runModelFallback,
  type FallbackModel,
  type FallbackOutcome,
} from "./retry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const categories = [
  "Póló", "Galléros", "cable knit", "vékony kötött", "sleepwear", "zipup", "farmer", "nadrág",
  "dzseki", "hoodie", "quarter zip", "short", "jort", "öv", "sapka",
  "mez", "cipő", "mellény", "ing", "nyakkendő", "zakó/öltöny", "crewneck", "kabát", "szoknya", "hosszúujjú",
  "melegítő nadrág", "sál", "táska", "ruha", "other",
];
const genders = ["női", "férfi"];

const models = [
  { provider: "gemini", id: "gemini-3.1-flash-lite", envKey: "GEMINI_API_KEY" },
  { provider: "gemini", id: "gemini-3.5-flash-lite", envKey: "GEMINI_API_KEY" },
  { provider: "openai", id: "gpt-6-luna", envKey: "OPENAI_API_KEY" },
] as const;

const attemptsPerModel = 3;
const requestTimeoutMs = 12_000;
const retryBaseDelayMs = 500;
const retryMaxDelayMs = 4_000;
const modelHealthTableFunctions = [
  "claim_ai_model",
  "record_ai_model_success",
  "record_ai_model_failure",
] as const;

class CircuitState {
  private readonly openUntil = new Map<string, number>();
  private readonly failures = new Map<string, number>();
  private readonly probeLeases = new Map<string, number>();

  claim(model: string): boolean {
    const cooldownUntil = this.openUntil.get(model);
    if (cooldownUntil === undefined) return true;
    if (Date.now() < cooldownUntil) return false;
    const leaseUntil = this.probeLeases.get(model) ?? 0;
    if (Date.now() < leaseUntil) return false;
    this.probeLeases.set(model, Date.now() + 90_000);
    return true;
  }

  success(model: string): void {
    this.failures.delete(model);
    this.openUntil.delete(model);
    this.probeLeases.delete(model);
  }

  failure(model: string): number {
    const count = (this.failures.get(model) ?? 0) + 1;
    this.failures.set(model, count);
    this.probeLeases.delete(model);
    const cooldownMs = Math.min(30 * 60_000, 60_000 * 2 ** (count - 1));
    this.openUntil.set(model, Date.now() + cooldownMs);
    return cooldownMs;
  }
}

const localCircuitState = new CircuitState();
let sharedHealthStoreUnavailable = false;
let healthStoreWarningLogged = false;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function healthRpc(functionName: (typeof modelHealthTableFunctions)[number], body: unknown) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Supabase service role configuration is unavailable");
  }

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${functionName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) {
    throw new Error(`Model health RPC ${functionName} returned ${response.status}`);
  }
  return functionName === "claim_ai_model" || functionName === "record_ai_model_failure"
    ? await response.json()
    : null;
}

async function modelIsAvailable(model: string): Promise<boolean> {
  if (sharedHealthStoreUnavailable) return localCircuitState.claim(model);
  try {
    return await healthRpc("claim_ai_model", {
      p_model_name: model,
      p_probe_lease_seconds: 90,
    }) as boolean;
  } catch (error) {
    sharedHealthStoreUnavailable = true;
    if (!healthStoreWarningLogged) {
      console.error("Shared AI model health storage unavailable; using per-instance circuit state", error);
      healthStoreWarningLogged = true;
    }
    return localCircuitState.claim(model);
  }
}

async function recordModelSuccess(model: string): Promise<void> {
  localCircuitState.success(model);
  if (sharedHealthStoreUnavailable) return;
  try {
    await healthRpc("record_ai_model_success", { p_model_name: model });
  } catch (error) {
    sharedHealthStoreUnavailable = true;
    if (!healthStoreWarningLogged) {
      console.error("Could not update shared AI model health; using per-instance circuit state", error);
      healthStoreWarningLogged = true;
    }
  }
}

async function recordModelFailure(model: string): Promise<number> {
  const localCooldown = localCircuitState.failure(model);
  if (sharedHealthStoreUnavailable) return localCooldown;
  try {
    const cooldownSeconds = await healthRpc("record_ai_model_failure", {
      p_model_name: model,
    }) as number;
    return cooldownSeconds * 1000;
  } catch (error) {
    sharedHealthStoreUnavailable = true;
    if (!healthStoreWarningLogged) {
      console.error("Could not update shared AI model health; using per-instance circuit state", error);
      healthStoreWarningLogged = true;
    }
    return localCooldown;
  }
}

function makePrompt(task: "inventory" | "search"): string {
  return task === "inventory"
    ? `Analyze this clothing item in Hungarian. Choose ONE category from: ${categories.join(", ")}, and choose its gender from: ${genders.join(", ")}. Return a JSON object with name (string), brand (string), category (string), gender (string), price (number), color (string), pattern (string), condition (string, e.g. 'Új', 'Kiváló', 'Használt'), and size (string).`
    : `Analyze this clothing item. Identify its category (choose EXACTLY ONE from: ${categories.join(", ")}) and gender (choose EXACTLY ONE from: ${genders.join(", ")}), its main color in Hungarian, and its pattern in Hungarian. Return a JSON object with category (string), gender (string), color (string), and pattern (string).`;
}

async function readProviderError(response: Response): Promise<string> {
  const body = await response.text().catch(() => "");
  try {
    const parsed = JSON.parse(body);
    return parsed?.error?.message ?? parsed?.error?.status ?? `HTTP ${response.status}`;
  } catch {
    return `HTTP ${response.status}`;
  }
}

function extractJsonObject(text: unknown): Record<string, unknown> {
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new Error("Model returned no text");
  }
  const result = JSON.parse(text);
  if (result === null || typeof result !== "object" || Array.isArray(result)) {
    throw new Error("Model returned invalid JSON output");
  }
  return result as Record<string, unknown>;
}

async function callGemini(model: FallbackModel, apiKey: string, prompt: string, imageBase64: string, mimeType: string) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model.id}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }, { inlineData: { mimeType, data: imageBase64 } }] }],
        generationConfig: { responseMimeType: "application/json" },
      }),
      signal: AbortSignal.timeout(requestTimeoutMs),
    },
  );

  if (!response.ok) {
    const message = await readProviderError(response);
    throw new ProviderError(message, model.provider, model.id, response.status, isRetryableStatus(response.status));
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: unknown }) => part.text)
    .find((part: unknown) => typeof part === "string");
  try {
    return extractJsonObject(text);
  } catch (error) {
    throw new ProviderError(String(error), model.provider, model.id, 502, true);
  }
}

async function callOpenAi(model: FallbackModel, apiKey: string, prompt: string, imageBase64: string, mimeType: string) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model: model.id,
      input: [{
        role: "user",
        content: [
          { type: "input_text", text: prompt },
          { type: "input_image", image_url: `data:${mimeType};base64,${imageBase64}` },
        ],
      }],
      text: { format: { type: "json_object" } },
      max_output_tokens: 1200,
    }),
    signal: AbortSignal.timeout(requestTimeoutMs),
  });

  if (!response.ok) {
    const message = await readProviderError(response);
    throw new ProviderError(message, model.provider, model.id, response.status, isRetryableStatus(response.status));
  }

  const data = await response.json();
  const text = data?.output
    ?.flatMap((item: { content?: Array<{ type?: string; text?: unknown }> }) => item.content ?? [])
    .find((item: { type?: string }) => item.type === "output_text")?.text;
  try {
    return extractJsonObject(text);
  } catch (error) {
    throw new ProviderError(String(error), model.provider, model.id, 502, true);
  }
}

async function callModel(model: FallbackModel, apiKey: string, prompt: string, imageBase64: string, mimeType: string) {
  return model.provider === "gemini"
    ? await callGemini(model, apiKey, prompt, imageBase64, mimeType)
    : await callOpenAi(model, apiKey, prompt, imageBase64, mimeType);
}

async function analyzeWithFallback(
  prompt: string,
  imageBase64: string,
  mimeType: string,
): Promise<FallbackOutcome<Record<string, unknown>>> {
  return runModelFallback({
    models,
    attemptsPerModel,
    retryBaseDelayMs,
    retryMaxDelayMs,
    getApiKey: (model) => Deno.env.get(model.envKey),
    isAvailable: (model) => modelIsAvailable(model.id),
    callModel: (model, apiKey) => callModel(model, apiKey, prompt, imageBase64, mimeType),
    recordSuccess: (model) => recordModelSuccess(model.id),
    recordFailure: (model) => recordModelFailure(model.id),
    wait: sleep,
    onEvent: (event) => {
      if (event.type === "success") {
        console.info(`Image analysis succeeded with ${event.model} (attempt ${event.attempt})`);
      } else if (event.type === "retry") {
        console.warn(`${event.model} failed; retrying in ${event.delayMs} ms`, event.detail);
      } else if (event.type === "failure") {
        console.error(
          `${event.model} failed (attempt ${event.attempt}, status ${event.status ?? "network"})`,
          event.detail,
        );
      } else if (event.type === "cooldown") {
        console.warn(`${event.model} cooling down for about ${Math.round(event.cooldownMs / 1000)} seconds`);
      } else {
        console.info(`Skipping ${event.model}: ${event.detail}`);
      }
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const body = await request.json();
    const task = body.task;
    const imageBase64 = body.imageBase64;
    const mimeType = body.mimeType;

    if (task !== "inventory" && task !== "search") {
      return jsonResponse({ error: "Unsupported analysis task" }, 400);
    }
    if (typeof imageBase64 !== "string" || imageBase64.length === 0 || imageBase64.length > 12_000_000) {
      return jsonResponse({ error: "Image is missing or too large" }, 400);
    }
    if (mimeType !== "image/jpeg" && mimeType !== "image/png" && mimeType !== "image/webp") {
      return jsonResponse({ error: "Unsupported image type" }, 400);
    }

    const result = await analyzeWithFallback(makePrompt(task), imageBase64, mimeType);
    if (!result.ok) return jsonResponse(result, 503);
    return jsonResponse(result.result);
  } catch (error) {
    console.error("Gemini vision function error", error);
    return jsonResponse({ error: "Could not analyze image" }, 500);
  }
});
