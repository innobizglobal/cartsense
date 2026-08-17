import { compareCartWithMemory } from "@/lib/fmcg-analytics";
import { json, options } from "@/lib/api-response";

export async function OPTIONS() {
  return options();
}

export async function POST(request: Request) {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return json({
      error: "Send JSON cart items.",
      code: "INVALID_CONTENT_TYPE",
    }, { status: 415 });
  }

  try {
    return json(compareCartWithMemory(await request.json()));
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Cart comparison failed.",
      code: "CART_COMPARE_FAILED",
    }, { status: 400 });
  }
}
