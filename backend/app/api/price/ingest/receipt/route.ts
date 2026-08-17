import { ingestAnonymousReceipt } from "@/lib/fmcg-analytics";
import { json, options } from "@/lib/api-response";

export async function OPTIONS() {
  return options();
}

export async function POST(request: Request) {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return json({
      error: "Send JSON receipt price memory.",
      code: "INVALID_CONTENT_TYPE",
    }, { status: 415 });
  }

  try {
    return json(ingestAnonymousReceipt(await request.json(), "receipt"));
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Anonymous receipt ingest failed.",
      code: "INGEST_FAILED",
    }, { status: 400 });
  }
}
