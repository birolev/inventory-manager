const DIMENSIONS = 1536;
const MAX_IMAGE_BYTES = 6_000_000;
const localOrigins = new Set(["http://localhost", "http://127.0.0.1"]);
const productionOrigins = (Deno.env.get("APP_ORIGINS") ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

function corsHeaders(origin: string | null): Record<string, string> {
  const base = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (!origin) return base;
  let allowed = productionOrigins.includes(origin);
  try {
    const url = new URL(origin);
    allowed ||= url.protocol === "http:" &&
      localOrigins.has(`${url.protocol}//${url.hostname}`);
  } catch {
    // Invalid origins are rejected below.
  }
  return {
    ...base,
    ...(allowed ? { "Access-Control-Allow-Origin": origin } : {}),
  };
}

function json(body: unknown, status = 200, origin: string | null = null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") {
    if (origin && !corsHeaders(origin)["Access-Control-Allow-Origin"]) {
      return json({ error: "Origin not allowed" }, 403, origin);
    }
    return new Response("ok", { headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, origin);
  }
  try {
    const authorization = request.headers.get("authorization") ?? "";
    const token = /^Bearer\s+(\S+)$/i.exec(authorization)?.[1];
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!token || !supabaseUrl || !anonKey) {
      return json({ error: "Authentication required" }, 401, origin);
    }
    const auth = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!auth.ok) {
      return json({ error: "Authentication required" }, 401, origin);
    }
    const user = await auth.json();
    if (typeof user?.id !== "string" || user.is_anonymous === true) {
      return json({ error: "Authentication required" }, 401, origin);
    }

    const body = await request.json();
    const mimeType = body?.mimeType;
    const imageBase64 = body?.imageBase64;
    if (
      !(["image/jpeg", "image/png"].includes(mimeType)) ||
      typeof imageBase64 !== "string" ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
        imageBase64,
      ) ||
      imageBase64.length > Math.ceil(MAX_IMAGE_BYTES * 4 / 3) + 4
    ) {
      return json(
        { error: "Provide a JPEG or PNG image up to 6 MB" },
        400,
        origin,
      );
    }
    const googleKey = Deno.env.get("GEMINI_API_KEY");
    if (!googleKey) {
      return json({ error: "Image embedding is not configured" }, 503, origin);
    }
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent?key=${
        encodeURIComponent(googleKey)
      }`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          content: {
            parts: [{
              inlineData: { mimeType, data: imageBase64 },
            }],
          },
          outputDimensionality: DIMENSIONS,
        }),
        signal: AbortSignal.timeout(20_000),
      },
    );
    if (!response.ok) {
      const providerBody = await response.text().catch(() => "");
      let providerMessage = providerBody;
      try {
        providerMessage = JSON.parse(providerBody)?.error?.message ??
          providerBody;
      } catch {
        // Retain the response text when the provider doesn't return JSON.
      }
      const detail = providerMessage.slice(0, 1000);
      console.error("Gemini image embedding failed", response.status, detail);
      return json(
        {
          error: "Could not create image embedding",
          providerStatus: response.status,
          detail,
        },
        response.status === 429 ? 429 : 502,
        origin,
      );
    }
    const result = await response.json();
    const values = result?.embedding?.values;
    if (
      !Array.isArray(values) || values.length !== DIMENSIONS ||
      values.some((v: unknown) => typeof v !== "number" || !Number.isFinite(v))
    ) {
      console.error("Gemini returned an invalid image embedding");
      return json({ error: "Could not create image embedding" }, 502, origin);
    }
    return json(
      {
        embedding: values,
        model: "gemini-embedding-2",
        dimensions: DIMENSIONS,
      },
      200,
      origin,
    );
  } catch (error) {
    console.error(
      "Image embedding request failed",
      error instanceof Error ? error.message : "unknown error",
    );
    return json({ error: "Could not create image embedding" }, 500, origin);
  }
});
