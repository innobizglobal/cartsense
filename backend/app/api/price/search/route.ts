import { searchPrices } from "@/lib/price-intelligence";
import { json, options } from "@/lib/api-response";

export async function OPTIONS() {
  return options();
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  return handle({
    query: url.searchParams.get("q") ?? url.searchParams.get("query") ?? "",
    pincode: url.searchParams.get("pincode") ?? undefined,
    providers: url.searchParams.get("providers")?.split(",").map((value) => value.trim()),
    limit: url.searchParams.get("limit") ?? undefined,
  });
}

export async function POST(request: Request) {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return json({ error: "Send JSON with query, pincode and providers.", code: "INVALID_CONTENT_TYPE" }, { status: 415 });
  }
  return handle(await request.json());
}

async function handle(input: unknown) {
  try {
    return json(await searchPrices(input));
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Price lookup failed.",
      code: "PRICE_LOOKUP_FAILED",
    }, { status: 400 });
  }
}
