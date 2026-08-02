import { env } from "cloudflare:workers";
import { extractResponseText, normalizeReceipt, receiptJsonSchema, receiptPrompt } from "@/lib/receipt-ai";

const maximumImageBytes = 12 * 1024 * 1024;
const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

function imageType(file: File) {
  if (allowedTypes.has(file.type)) return file.type;
  const lower = file.name.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  return null;
}

interface RuntimeEnv {
  DB: D1Database;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  CARTSENSE_DAILY_SCAN_LIMIT?: string;
}

function runtimeEnv() {
  return env as unknown as RuntimeEnv;
}

async function clientHash(request: Request) {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const device = (request.headers.get("x-cartsense-device") ?? "unknown").slice(0, 128);
  const bytes = new TextEncoder().encode(`${ip}|${device}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function consumeScan(request: Request) {
  const bindings = runtimeEnv();
  const parsedLimit = Number.parseInt(bindings.CARTSENSE_DAILY_SCAN_LIMIT ?? "20", 10);
  const limit = Math.min(100, Math.max(1, Number.isFinite(parsedLimit) ? parsedLimit : 20));
  const bucket = new Date().toISOString().slice(0, 10);
  const hash = await clientHash(request);
  const existing = await bindings.DB.prepare(
    "SELECT scan_count AS scanCount FROM scan_usage WHERE bucket = ? AND client_hash = ?",
  ).bind(bucket, hash).first<{ scanCount: number }>();
  const count = existing?.scanCount ?? 0;
  if (count >= limit) return { allowed: false, remaining: 0 };
  await bindings.DB.prepare(
    `INSERT INTO scan_usage (bucket, client_hash, scan_count, updated_at)
     VALUES (?, ?, 1, ?)
     ON CONFLICT(bucket, client_hash) DO UPDATE SET
       scan_count = scan_count + 1,
       updated_at = excluded.updated_at`,
  ).bind(bucket, hash, new Date().toISOString()).run();
  return { allowed: true, remaining: Math.max(0, limit - count - 1) };
}

function errorResponse(message: string, status: number, code: string) {
  return Response.json({ error: message, code }, { status });
}

export async function POST(request: Request) {
  const bindings = runtimeEnv();
  if (!bindings.OPENAI_API_KEY) {
    return errorResponse("AI receipt recognition is not configured.", 503, "AI_NOT_CONFIGURED");
  }

  const declaredLength = Number.parseInt(request.headers.get("content-length") ?? "0", 10);
  if (declaredLength > maximumImageBytes + 1024 * 256) {
    return errorResponse("The receipt photo is too large. Choose a photo below 12 MB.", 413, "IMAGE_TOO_LARGE");
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return errorResponse("Send the receipt as a multipart image upload.", 400, "INVALID_UPLOAD");
  }
  const image = form.get("receipt");
  if (!(image instanceof File)) {
    return errorResponse("No receipt photo was supplied.", 400, "IMAGE_REQUIRED");
  }
  const effectiveImageType = imageType(image);
  if (effectiveImageType == null) {
    return errorResponse("Use a JPEG, PNG or WebP receipt photo.", 415, "IMAGE_TYPE_UNSUPPORTED");
  }
  if (image.size <= 0 || image.size > maximumImageBytes) {
    return errorResponse("The receipt photo must be between 1 byte and 12 MB.", 413, "IMAGE_TOO_LARGE");
  }

  let allowance: { allowed: boolean; remaining: number };
  try {
    allowance = await consumeScan(request);
  } catch {
    return errorResponse("The receipt service is temporarily unavailable.", 503, "RATE_LIMIT_UNAVAILABLE");
  }
  if (!allowance.allowed) {
    return errorResponse("Today's AI scan limit has been reached. Private on-device scanning is still available.", 429, "DAILY_LIMIT_REACHED");
  }

  const base64 = Buffer.from(await image.arrayBuffer()).toString("base64");
  let upstream: Response;
  try {
    upstream = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        authorization: `Bearer ${bindings.OPENAI_API_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: bindings.OPENAI_MODEL ?? "gpt-5.6-terra",
        store: false,
        max_output_tokens: 12000,
        input: [{
          role: "user",
          content: [
            { type: "input_text", text: receiptPrompt },
            { type: "input_image", image_url: `data:${effectiveImageType};base64,${base64}`, detail: "original" },
          ],
        }],
        text: {
          format: {
            type: "json_schema",
            name: "grocery_receipt",
            strict: true,
            schema: receiptJsonSchema,
          },
        },
      }),
      signal: AbortSignal.timeout(90000),
    });
  } catch {
    return errorResponse("The AI reader could not be reached. Try again or use private scanning.", 502, "AI_UNREACHABLE");
  }

  if (!upstream.ok) {
    const retryable = upstream.status === 408 || upstream.status === 409 || upstream.status === 429 || upstream.status >= 500;
    return errorResponse(
      retryable ? "The AI reader is busy. Please try again shortly." : "The AI reader could not process this receipt.",
      retryable ? 503 : 422,
      "AI_REQUEST_FAILED",
    );
  }

  try {
    const payload = await upstream.json() as Record<string, unknown>;
    const receipt = normalizeReceipt(JSON.parse(extractResponseText(payload)) as Record<string, unknown>);
    return Response.json({ receipt }, {
      headers: {
        "cache-control": "no-store",
        "x-cartsense-scans-remaining": String(allowance.remaining),
      },
    });
  } catch {
    return errorResponse("The AI result was incomplete. Retake the photo with the whole receipt visible.", 422, "AI_RESULT_INVALID");
  }
}
