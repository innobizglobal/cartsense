import { buildFmcgAnalyticsSummary } from "@/lib/fmcg-analytics";
import { json, options } from "@/lib/api-response";

export async function OPTIONS() {
  return options();
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  return json(buildFmcgAnalyticsSummary({
    month: url.searchParams.get("month") ?? undefined,
    limit: Number(url.searchParams.get("limit") ?? 10),
  }));
}
