const DIMENSIONS = 1536;
const MAX_IMAGE_BYTES = 6_000_000;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  try {
    const authorization = request.headers.get("authorization") ?? "";
    const token = /^Bearer\s+(\S+)$/i.exec(authorization)?.[1];
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!token || !supabaseUrl || !anonKey) {
      return json({ error: "Authentication required" }, 401);
    }
    const auth = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!auth.ok) return json({ error: "Authentication required" }, 401);
    const user = await auth.json();
    if (typeof user?.id !== "string" || user.is_anonymous === true) {
      return json({ error: "Authentication required" }, 401);
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
      return json({ error: "Provide a JPEG or PNG image up to 6 MB" }, 400);
    }
    const googleKey = Deno.env.get("GEMINI_API_KEY");
    if (!googleKey) {
      return json({ error: "Image embedding is not configured" }, 503);
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
      console.error("Gemini image embedding failed", response.status);
      return json({ error: "Could not create image embedding" }, 502);
    }
    const result = await response.json();
    const values = result?.embedding?.values;
    if (
      !Array.isArray(values) || values.length !== DIMENSIONS ||
      values.some((v: unknown) => typeof v !== "number" || !Number.isFinite(v))
    ) {
      console.error("Gemini returned an invalid image embedding");
      return json({ error: "Could not create image embedding" }, 502);
    }
    return json({
      embedding: values,
      model: "gemini-embedding-2",
      dimensions: DIMENSIONS,
    });
  } catch (error) {
    console.error(
      "Image embedding request failed",
      error instanceof Error ? error.message : "unknown error",
    );
    return json({ error: "Could not create image embedding" }, 500);
  }
});
