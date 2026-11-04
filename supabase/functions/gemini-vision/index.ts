import {
  ProviderError,
  isRetryableStatus,
  runModelFallback,
  type FallbackModel,
  type FallbackOutcome,
} from "./retry.ts";
import { MAX_REQUEST_BYTES, validateModelOutput, validateRequestBody } from "./validation.ts";

const localOrigins = new Set(["http://localhost", "http://127.0.0.1"]);
const productionOrigins = (Deno.env.get("APP_ORIGINS") ?? "").split(",").map((origin) => origin.trim()).filter(Boolean);
function corsHeaders(origin: string | null): Record<string, string> {
  if (!origin) return { "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", Vary: "Origin" };
  let allowed = productionOrigins.includes(origin);
  try {
    const url = new URL(origin);
    allowed ||= url.protocol === "http:" && localOrigins.has(`${url.protocol}//${url.hostname}`);
  } catch { /* Invalid Origin is rejected. */ }
  return {
    ...(allowed ? { "Access-Control-Allow-Origin": origin } : {}),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

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
  "claim_ai_model_for_edge",
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
const healthCache = new Map<string, { value: boolean; expiresAt: number }>();
let sharedHealthStoreUnavailable = false;
let healthStoreWarningLogged = false;

function jsonResponse(body: unknown, status = 200, origin: string | null = null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readBodyWithinLimit(request: Request, maxBytes: number): Promise<string | null> {
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
  try { return new TextDecoder("utf-8", { fatal: true }).decode(body); } catch { return null; }
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
  return functionName === "claim_ai_model_for_edge" || functionName === "record_ai_model_failure"
    ? await response.json()
    : null;
}

async function modelIsAvailable(model: string): Promise<boolean> {
  if (sharedHealthStoreUnavailable) return localCircuitState.claim(model);
  const cached = healthCache.get(model);
  if (cached && cached.expiresAt > Date.now()) return cached.value;
  try {
    const state = await healthRpc("claim_ai_model_for_edge", {
      p_model_name: model,
      p_probe_lease_seconds: 90,
    }) as string;
    if (state === "available") healthCache.set(model, { value: true, expiresAt: Date.now() + 5_000 });
    if (state === "blocked") healthCache.set(model, { value: false, expiresAt: Date.now() + 5_000 });
    // A half-open probe lease is never cached, preserving its single-caller guarantee.
    return state === "available" || state === "probe";
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
  healthCache.delete(model);
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
  healthCache.delete(model);
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

async function callGemini(model: FallbackModel, apiKey: string, prompt: string, imageBase64: string, mimeType: string, signal: AbortSignal) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model.id}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }, { inlineData: { mimeType, data: imageBase64 } }] }],
        generationConfig: { responseMimeType: "application/json" },
      }),
      signal: AbortSignal.any([signal, AbortSignal.timeout(requestTimeoutMs)]),
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

async function callOpenAi(model: FallbackModel, apiKey: string, prompt: string, imageBase64: string, mimeType: string, signal: AbortSignal) {
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
    signal: AbortSignal.any([signal, AbortSignal.timeout(requestTimeoutMs)]),
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

async function callModel(model: FallbackModel, apiKey: string, prompt: string, imageBase64: string, mimeType: string, signal: AbortSignal) {
  return model.provider === "gemini"
    ? await callGemini(model, apiKey, prompt, imageBase64, mimeType, signal)
    : await callOpenAi(model, apiKey, prompt, imageBase64, mimeType, signal);
}

async function analyzeWithFallback(
  prompt: string,
  imageBase64: string,
  mimeType: string,
  signal: AbortSignal,
): Promise<FallbackOutcome<Record<string, unknown>>> {
  return runModelFallback({
    models,
    attemptsPerModel,
    retryBaseDelayMs,
    retryMaxDelayMs,
    getApiKey: (model) => Deno.env.get(model.envKey),
    isAvailable: (model) => modelIsAvailable(model.id),
    callModel: (model, apiKey) => callModel(model, apiKey, prompt, imageBase64, mimeType, signal),
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
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (origin && !corsHeaders(origin)["Access-Control-Allow-Origin"]) return jsonResponse({ error: "Origin not allowed" }, 403, origin);
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405, origin);

  try {
    const authorization = request.headers.get("authorization") ?? "";
    const tokenMatch = /^Bearer\s+(\S+)$/i.exec(authorization);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!tokenMatch || !supabaseUrl || !anonKey) return jsonResponse({ error: "Authentication required" }, 401, origin);
    const authResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${tokenMatch[1]}` },
      signal: AbortSignal.timeout(5_000),
    });
    if (!authResponse.ok) return jsonResponse({ error: "Authentication required" }, 401, origin);
    const user = await authResponse.json();
    if (typeof user?.id !== "string" || user.is_anonymous === true) return jsonResponse({ error: "Authentication required" }, 401, origin);

    if (!(request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json")) {
      return jsonResponse({ error: "Invalid request" }, 415, origin);
    }
    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_REQUEST_BYTES) return jsonResponse({ error: "Invalid request" }, 413, origin);
    const rawBody = await readBodyWithinLimit(request, MAX_REQUEST_BYTES);
    if (rawBody === null) return jsonResponse({ error: "Invalid request" }, 413, origin);
    let parsedBody: unknown;
    try { parsedBody = JSON.parse(rawBody); } catch { return jsonResponse({ error: "Invalid request" }, 400, origin); }
    const body = validateRequestBody(parsedBody);
    if (!body) return jsonResponse({ error: "Invalid request" }, 400, origin);

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return jsonResponse({ error: "Service temporarily unavailable" }, 503, origin);
    const quotaResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/consume_ai_analysis_quota`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      body: JSON.stringify({ p_user_id: user.id }),
      signal: AbortSignal.timeout(5_000),
    });
    if (!quotaResponse.ok) {
      console.error("AI quota service unavailable", quotaResponse.status);
      return jsonResponse({ error: "Service temporarily unavailable" }, 503, origin);
    }
    if (await quotaResponse.json() !== true) return jsonResponse({ error: "Daily analysis limit reached" }, 429, origin);

    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), 25_000);
    let result: FallbackOutcome<Record<string, unknown>>;
    try {
      result = await Promise.race([
        analyzeWithFallback(makePrompt(body.task), body.imageBase64, body.mimeType, controller.signal),
        new Promise<never>((_, reject) => controller.signal.addEventListener("abort", () => reject(new Error("deadline")), { once: true })),
      ]);
    } finally { clearTimeout(deadline); }
    if (!result.ok) return jsonResponse({ error: "Analysis is temporarily unavailable. Please try again shortly." }, 503, origin);
    const safeOutput = validateModelOutput(result.result, body.task, categories, genders);
    if (!safeOutput) {
      console.error("AI provider returned invalid structured output");
      return jsonResponse({ error: "Could not analyze image" }, 502, origin);
    }
    // Keep response fields at the top level for compatibility with existing app builds.
    return jsonResponse({ ...safeOutput, _model: result.model }, 200, origin);
  } catch (error) {
    const timedOut = error instanceof Error && error.message === "deadline";
    console.error("Image analysis request failed", timedOut ? "deadline exceeded" : error instanceof Error ? error.message : "unknown error");
    return jsonResponse({ error: timedOut ? "Analysis timed out. Please try again." : "Could not analyze image" }, timedOut ? 504 : 500, origin);
  }
});
