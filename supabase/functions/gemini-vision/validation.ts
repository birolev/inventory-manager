export const MAX_REQUEST_BYTES = 9_000_000;
export const MAX_IMAGE_BYTES = 6_000_000;
export const MAX_IMAGE_DIMENSION = 8_000;

export type AnalysisTask = "inventory" | "search";

export function parseImageDimensions(data: Uint8Array, mimeType: string): { width: number; height: number } | null {
  if (mimeType === "image/png" && data.length >= 24 &&
    data[0] === 0x89 && data[1] === 0x50 && data[2] === 0x4e && data[3] === 0x47 &&
    String.fromCharCode(...data.subarray(12, 16)) === "IHDR") {
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (mimeType === "image/webp" && data.length >= 30 &&
    String.fromCharCode(...data.subarray(0, 4)) === "RIFF" &&
    String.fromCharCode(...data.subarray(8, 12)) === "WEBP") {
    const kind = String.fromCharCode(...data.subarray(12, 16));
    if (kind === "VP8X") {
      return {
        width: 1 + data[24] + (data[25] << 8) + (data[26] << 16),
        height: 1 + data[27] + (data[28] << 8) + (data[29] << 16),
      };
    }
    if (kind === "VP8L" && data[20] === 0x2f) {
      return {
        width: 1 + data[21] + ((data[22] & 0x3f) << 8),
        height: 1 + (data[22] >> 6) + (data[23] << 2) + ((data[24] & 0x0f) << 10),
      };
    }
    if (kind === "VP8 " && data.length >= 30 && data[23] === 0x9d && data[24] === 0x01 && data[25] === 0x2a) {
      const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
      return { width: view.getUint16(26, true) & 0x3fff, height: view.getUint16(28, true) & 0x3fff };
    }
  }
  if (mimeType === "image/jpeg" && data.length >= 4 && data[0] === 0xff && data[1] === 0xd8) {
    let offset = 2;
    while (offset + 4 <= data.length) {
      if (data[offset] !== 0xff) return null;
      const marker = data[offset + 1];
      offset += 2;
      if (marker === 0xd8 || marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      const length = (data[offset] << 8) | data[offset + 1];
      if (length < 2 || offset + length > data.length) return null;
      if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
        return { height: (data[offset + 3] << 8) | data[offset + 4], width: (data[offset + 5] << 8) | data[offset + 6] };
      }
      offset += length;
    }
  }
  return null;
}

export function validateImageBase64(value: unknown, mimeType: unknown): string | null {
  if (mimeType !== "image/jpeg" && mimeType !== "image/png" && mimeType !== "image/webp") return null;
  if (typeof value !== "string" || value.length === 0 || value.length > Math.ceil(MAX_IMAGE_BYTES * 4 / 3) + 4) return null;
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) return null;
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(value), (char) => char.charCodeAt(0)); } catch { return null; }
  if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) return null;
  const dimensions = parseImageDimensions(bytes, mimeType);
  if (!dimensions || dimensions.width < 1 || dimensions.height < 1 ||
    dimensions.width > MAX_IMAGE_DIMENSION || dimensions.height > MAX_IMAGE_DIMENSION ||
    dimensions.width * dimensions.height > 20_000_000) return null;
  return value;
}

export function validateModelOutput(value: unknown, task: AnalysisTask, categories: readonly string[], genders: readonly string[]): Record<string, unknown> | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  const fields = task === "inventory"
    ? ["name", "brand", "category", "gender", "price", "color", "pattern", "condition", "size"]
    : ["category", "gender", "color", "pattern"];
  if (Object.keys(input).some((key) => !fields.includes(key))) return null;
  if (fields.some((key) => !Object.hasOwn(input, key))) return null;
  const strings = task === "inventory" ? fields.filter((key) => key !== "price") : fields;
  if (strings.some((key) => typeof input[key] !== "string" || (input[key] as string).length > 200)) return null;
  if (!categories.includes(input.category as string) || !genders.includes(input.gender as string)) return null;
  if (task === "inventory" && (typeof input.price !== "number" || !Number.isFinite(input.price) || input.price < 0 || input.price > 1_000_000)) return null;
  return Object.fromEntries(fields.map((key) => [key, input[key]]));
}

export function validateRequestBody(value: unknown): { task: AnalysisTask; imageBase64: string; mimeType: string } | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  if (Object.keys(body).some((key) => !["task", "imageBase64", "mimeType"].includes(key))) return null;
  if (body.task !== "inventory" && body.task !== "search") return null;
  if (typeof body.mimeType !== "string") return null;
  const imageBase64 = validateImageBase64(body.imageBase64, body.mimeType);
  if (!imageBase64) return null;
  return { task: body.task, imageBase64, mimeType: body.mimeType };
}
