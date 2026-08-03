import { env } from "cloudflare:workers";
import {
  extractResponseText,
  imageType,
  normalizeReceipt,
  receiptAuditPrompt,
  receiptJsonSchema,
  receiptPrompt,
  shouldAuditReceipt,
} from "@/lib/receipt-ai";

const maximumImageBytes = 12 * 1024 * 1024;
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
  if (count >= limit) return { allowed: false, remaining: 0, identifier: hash };
  await bindings.DB.prepare(
    `INSERT INTO scan_usage (bucket, client_hash, scan_count, updated_at)
     VALUES (?, ?, 1, ?)
     ON CONFLICT(bucket, client_hash) DO UPDATE SET
       scan_count = scan_count + 1,
       updated_at = excluded.updated_at`,
  ).bind(bucket, hash, new Date().toISOString()).run();
  return {
    allowed: true,
    remaining: Math.max(0, limit - count - 1),
    identifier: hash,
  };
}

function errorResponse(message: string, status: number, code: string) {
  return Response.json({ error: message, code }, { status });
}

class ModelRequestError extends Error {
  constructor(readonly status: number) {
    super(`OpenAI request failed with status ${status}`);
  }
}

async function analyzeReceipt(
  bindings: RuntimeEnv,
  imageUrls: string[],
  prompt: string,
  safetyIdentifier: string,
) {
  const imageContent = imageUrls.map((imageUrl, index) => ({
    type: "input_image",
    image_url: imageUrl,
    detail: "original",
  } satisfies const));
  const upstream = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${bindings.OPENAI_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: bindings.OPENAI_MODEL ?? "gpt-5.6-terra",
      store: false,
      safety_identifier: safetyIdentifier,
      max_output_tokens: 12000,
      reasoning: { effort: "medium" },
      input: [{
        role: "user",
        content: [
          { type: "input_text", text: prompt },
          ...imageContent,
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
  if (!upstream.ok) throw new ModelRequestError(upstream.status);
  const payload = await upstream.json() as Record<string, unknown>;
  return normalizeReceipt(
    JSON.parse(extractResponseText(payload)) as Record<string, unknown>,
  );
}

export async function POST(request: Request) {
  const bindings = runtimeEnv();
  if (!bindings.OPENAI_API_KEY) {
    return errorResponse("AI receipt recognition is not configured.", 503, "AI_NOT_CONFIGURED");
  }

  const declaredLength = Number.parseInt(request.headers.get("content-length") ?? "0", 10);
  if (declaredLength > maximumImageBytes * 2 + 1024 * 512) {
    return errorResponse("The receipt photos are too large. Use fewer sections or retake closer photos.", 413, "IMAGE_TOO_LARGE");
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return errorResponse("Send the receipt as a multipart image upload.", 400, "INVALID_UPLOAD");
  }
  const images = form
    .getAll("receipt")
    .filter((value): value is File => value instanceof File);
  if (images.length === 0) {
    return errorResponse("No receipt photo was supplied.", 400, "IMAGE_REQUIRED");
  }
  if (images.length > 4) {
    return errorResponse("Use up to 4 ordered photos for one long receipt.", 400, "TOO_MANY_IMAGES");
  }
  const effectiveImageTypes: string[] = [];
  let totalImageBytes = 0;
  for (const image of images) {
    const effectiveImageType = await imageType(image);
    if (effectiveImageType == null) {
      return errorResponse("Use JPEG, PNG or WebP receipt photos.", 415, "IMAGE_TYPE_UNSUPPORTED");
    }
    if (image.size <= 0 || image.size > maximumImageBytes) {
      return errorResponse("Each receipt photo must be between 1 byte and 12 MB.", 413, "IMAGE_TOO_LARGE");
    }
    totalImageBytes += image.size;
    effectiveImageTypes.push(effectiveImageType);
  }
  if (totalImageBytes > maximumImageBytes * 2) {
    return errorResponse("The long receipt photos are too large together. Retake them closer to the bill or use fewer sections.", 413, "IMAGE_TOO_LARGE");
  }

  let allowance: { allowed: boolean; remaining: number; identifier: string };
  try {
    allowance = await consumeScan(request);
  } catch {
    return errorResponse("The receipt service is temporarily unavailable.", 503, "RATE_LIMIT_UNAVAILABLE");
  }
  if (!allowance.allowed) {
    return errorResponse("Today's AI scan limit has been reached. Private on-device scanning is still available.", 429, "DAILY_LIMIT_REACHED");
  }

  const imageUrls = await Promise.all(images.map(async (image, index) => {
    const base64 = Buffer.from(await image.arrayBuffer()).toString("base64");
    return `data:${effectiveImageTypes[index]};base64,${base64}`;
  }));
  let receipt: Awaited<ReturnType<typeof analyzeReceipt>>;
  try {
    receipt = await analyzeReceipt(
      bindings,
      imageUrls,
      receiptPrompt,
      allowance.identifier,
    );
    if (shouldAuditReceipt(receipt)) {
      try {
        receipt = await analyzeReceipt(
          bindings,
          imageUrls,
          receiptAuditPrompt(receipt),
          allowance.identifier,
        );
      } catch {
        receipt.warnings = [
          ...receipt.warnings,
          "The second AI cross-check was unavailable; review highlighted details.",
        ];
      }
    }
    return Response.json({ receipt }, {
      headers: {
        "cache-control": "no-store",
        "x-cartsense-scans-remaining": String(allowance.remaining),
      },
    });
  } catch (error) {
    if (error instanceof ModelRequestError) {
      const retryable = error.status === 408 || error.status === 409 ||
        error.status === 429 || error.status >= 500;
      return errorResponse(
        retryable
          ? "The AI reader is busy. Please try again shortly."
          : "The AI reader could not process this receipt.",
        retryable ? 503 : 422,
        "AI_REQUEST_FAILED",
      );
    }
    if (error instanceof DOMException && error.name === "TimeoutError") {
      return errorResponse(
        "The AI reader took too long. Try again or use private scanning.",
        504,
        "AI_TIMEOUT",
      );
    }
    return errorResponse("The AI result was incomplete. Retake the photo with the whole receipt visible.", 422, "AI_RESULT_INVALID");
  }
}
