import {
  MAX_IMAGE_DIMENSION,
  parseImageDimensions,
  validateImageBase64,
  validateModelOutput,
  validateRequestBody,
} from "./validation.ts";

const categories = ["other", "PÃ³lÃ³"];
const genders = ["nÅ‘i", "fÃ©rfi"];
const png1px = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP2sAAAAASUVORK5CYII=";

Deno.test("accepts a supported image with valid dimensions", () => {
  if (!validateImageBase64(png1px, "image/png")) throw new Error("valid PNG rejected");
});

Deno.test("rejects mismatched MIME, malformed base64, and oversized dimensions", () => {
  if (validateImageBase64(png1px, "image/jpeg")) throw new Error("MIME mismatch accepted");
  if (validateImageBase64("%%%", "image/png")) throw new Error("malformed base64 accepted");
  const header = new Uint8Array(24);
  header.set([0x89, 0x50, 0x4e, 0x47], 0);
  new DataView(header.buffer).setUint32(16, MAX_IMAGE_DIMENSION + 1);
  new DataView(header.buffer).setUint32(20, 1);
  const encoded = btoa(String.fromCharCode(...header));
  if (validateImageBase64(encoded, "image/png")) throw new Error("oversized image accepted");
});

Deno.test("rejects unknown request fields and missing image", () => {
  if (validateRequestBody({ task: "search", imageBase64: png1px, mimeType: "image/png", extra: true })) {
    throw new Error("unknown property accepted");
  }
  if (validateRequestBody({ task: "search", mimeType: "image/png" })) throw new Error("missing image accepted");
});

Deno.test("accepts only strict, bounded model output", () => {
  const valid = { category: "other", gender: "fÃ©rfi", color: "kÃ©k", pattern: "plain" };
  if (!validateModelOutput(valid, "search", categories, genders)) throw new Error("valid output rejected");
  if (validateModelOutput({ ...valid, extra: "injected" }, "search", categories, genders)) throw new Error("extra model field accepted");
  if (validateModelOutput({ ...valid, category: "not a category" }, "search", categories, genders)) throw new Error("invalid category accepted");
});

Deno.test("rejects unsupported image bytes", () => {
  if (parseImageDimensions(new Uint8Array([1, 2, 3, 4]), "image/webp")) throw new Error("invalid bytes accepted");
});
