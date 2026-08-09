import { searchPrices } from "@/lib/price-intelligence";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-cartsense-device",
};

function json(data: unknown, init?: ResponseInit) {
  return Response.json(data, {
    ...init,
    headers: {
      ...corsHeaders,
      ...(init?.headers ?? {}),
    },
  });
}

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: corsHeaders });
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
