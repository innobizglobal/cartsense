import { searchMemoryPrices } from "./fmcg-analytics";

export type PriceProviderId =
  | "receipt"
  | "shelf"
  | "demo"
  | "bigbasket"
  | "jiomart"
  | "swiggy_instamart"
  | "blinkit"
  | "zepto";

export interface PriceSearchInput {
  query: string;
  pincode?: string;
  providers?: PriceProviderId[];
  limit?: number;
}

export interface PriceOffer {
  provider: PriceProviderId;
  providerLabel: string;
  productName: string;
  brand?: string;
  packSize?: string;
  mrp?: number;
  sellingPrice: number;
  currency: "INR";
  availability: "in_stock" | "out_of_stock" | "unknown";
  productUrl?: string;
  imageUrl?: string;
  unitPrice?: number;
  unit?: string;
  confidence: number;
  lastCheckedAt: string;
  source: "live" | "demo" | "cache";
}

export interface PriceSearchResponse {
  query: string;
  normalizedQuery: string;
  pincode?: string;
  providers: PriceProviderId[];
  offers: PriceOffer[];
  warnings: string[];
  cached: boolean;
}

type FetchLike = typeof fetch;

const providerLabels: Record<PriceProviderId, string> = {
  receipt: "Saved receipt prices",
  shelf: "Shelf prices",
  demo: "CartSense demo prices",
  bigbasket: "BigBasket",
  jiomart: "JioMart",
  swiggy_instamart: "Swiggy Instamart",
  blinkit: "Blinkit",
  zepto: "Zepto",
};

const supportedProviders: PriceProviderId[] = ["receipt", "shelf", "demo", "bigbasket"];
const allKnownProviders = new Set<PriceProviderId>([
  "receipt",
  "shelf",
  "demo",
  "bigbasket",
  "jiomart",
  "swiggy_instamart",
  "blinkit",
  "zepto",
]);

const cache = new Map<string, { expiresAt: number; response: PriceSearchResponse }>();
const cacheTtlMs = 30 * 60 * 1000;

const demoCatalog = [
  { productName: "Tetley Classic Tea 250g", brand: "Tetley", packSize: "250g", mrp: 180, sellingPrice: 165 },
  { productName: "Tata Tea Gold 500g", brand: "Tata Tea", packSize: "500g", mrp: 340, sellingPrice: 318 },
  { productName: "Amul Taaza Milk 500ml", brand: "Amul", packSize: "500ml", mrp: 29, sellingPrice: 29 },
  { productName: "Gold Drop Sunflower Oil 1L", brand: "Gold Drop", packSize: "1L", mrp: 185, sellingPrice: 168 },
  { productName: "Surf Excel Detergent Powder 1kg", brand: "Surf Excel", packSize: "1kg", mrp: 245, sellingPrice: 226 },
  { productName: "Whisper Choice Sanitary Pads 20 pcs", brand: "Whisper", packSize: "20 pcs", mrp: 155, sellingPrice: 139 },
  { productName: "Tata Salt 1kg", brand: "Tata", packSize: "1kg", mrp: 28, sellingPrice: 26 },
  { productName: "Aashirvaad Atta 5kg", brand: "Aashirvaad", packSize: "5kg", mrp: 310, sellingPrice: 286 },
];

export function normalizeQuery(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\b(gm|gms|gram|grams)\b/g, "g")
    .replace(/\b(litre|liter|litres|liters)\b/g, "l")
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizePriceSearchInput(input: unknown): PriceSearchInput {
  const value = typeof input === "object" && input !== null ? input as Record<string, unknown> : {};
  const query = String(value.query ?? "").trim();
  if (query.length < 2) throw new Error("Enter at least two letters to search prices.");
  if (query.length > 80) throw new Error("Search is too long. Please use a shorter product name.");

  const requestedProviders = Array.isArray(value.providers)
    ? value.providers.filter((provider): provider is PriceProviderId =>
        typeof provider === "string" && allKnownProviders.has(provider as PriceProviderId),
      )
    : undefined;
  const providers = requestedProviders?.length ? requestedProviders : ["receipt", "shelf", "demo", "bigbasket"];
  const pincode = String(value.pincode ?? "").replace(/\D/g, "").slice(0, 6) || undefined;
  const parsedLimit = Number(value.limit ?? 12);
  const limit = Math.min(30, Math.max(1, Number.isFinite(parsedLimit) ? parsedLimit : 12));

  return { query, pincode, providers, limit };
}

export function parseMoney(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return Number(value.toFixed(2));
  if (typeof value !== "string") return undefined;
  const cleaned = value.replace(/₹|rs\.?|inr|,/gi, "").trim();
  const match = cleaned.match(/\d+(?:\.\d{1,2})?/);
  if (!match) return undefined;
  const parsed = Number.parseFloat(match[0]);
  return Number.isFinite(parsed) ? Number(parsed.toFixed(2)) : undefined;
}

export function extractPackSize(name: string): string | undefined {
  const match = name.match(/\b(\d+(?:\.\d+)?)\s*(kg|g|gm|gms|l|ltr|litre|ml|pcs|pc|pieces)\b/i);
  if (!match) return undefined;
  const unit = match[2].toLowerCase().replace(/^gm?s?$/, "g").replace(/^ltr|litre$/, "l").replace(/^pieces?$/, "pcs");
  return `${match[1]}${unit}`;
}

export function addUnitPrice(offer: Omit<PriceOffer, "unitPrice" | "unit">): PriceOffer {
  const pack = offer.packSize ?? extractPackSize(offer.productName);
  if (!pack) return { ...offer, packSize: offer.packSize };
  const match = pack.match(/^(\d+(?:\.\d+)?)(kg|g|l|ml|pcs)$/i);
  if (!match) return { ...offer, packSize: pack };
  const quantity = Number.parseFloat(match[1]);
  const unit = match[2].toLowerCase();
  if (!Number.isFinite(quantity) || quantity <= 0) return { ...offer, packSize: pack };

  if (unit === "kg") return { ...offer, packSize: pack, unit: "kg", unitPrice: Number((offer.sellingPrice / quantity).toFixed(2)) };
  if (unit === "g") return { ...offer, packSize: pack, unit: "kg", unitPrice: Number((offer.sellingPrice / (quantity / 1000)).toFixed(2)) };
  if (unit === "l") return { ...offer, packSize: pack, unit: "l", unitPrice: Number((offer.sellingPrice / quantity).toFixed(2)) };
  if (unit === "ml") return { ...offer, packSize: pack, unit: "l", unitPrice: Number((offer.sellingPrice / (quantity / 1000)).toFixed(2)) };
  if (unit === "pcs") return { ...offer, packSize: pack, unit: "piece", unitPrice: Number((offer.sellingPrice / quantity).toFixed(2)) };
  return { ...offer, packSize: pack };
}

function resultScore(query: string, productName: string) {
  const terms = normalizeQuery(query).split(" ").filter(Boolean);
  const haystack = normalizeQuery(productName);
  if (haystack === normalizeQuery(query)) return 1;
  const matched = terms.filter((term) => haystack.includes(term)).length;
  return terms.length ? matched / terms.length : 0;
}

function demoSearch(input: PriceSearchInput): PriceOffer[] {
  const now = new Date().toISOString();
  return demoCatalog
    .map((item) => ({ item, score: resultScore(input.query, item.productName) }))
    .filter(({ score }) => score > 0)
    .sort((a, b) => b.score - a.score || a.item.sellingPrice - b.item.sellingPrice)
    .slice(0, input.limit ?? 12)
    .map(({ item, score }) =>
      addUnitPrice({
        provider: "demo",
        providerLabel: providerLabels.demo,
        productName: item.productName,
        brand: item.brand,
        packSize: item.packSize,
        mrp: item.mrp,
        sellingPrice: item.sellingPrice,
        currency: "INR",
        availability: "in_stock",
        confidence: Number(Math.max(0.55, Math.min(0.98, score)).toFixed(2)),
        lastCheckedAt: now,
        source: "demo",
      }),
    );
}

function tryJsonParse(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return undefined;
  }
}

function walkObjects(value: unknown, visitor: (record: Record<string, unknown>) => void, depth = 0) {
  if (depth > 8 || value == null) return;
  if (Array.isArray(value)) {
    for (const item of value) walkObjects(item, visitor, depth + 1);
    return;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    visitor(record);
    for (const item of Object.values(record)) walkObjects(item, visitor, depth + 1);
  }
}

export function parseEmbeddedProductOffers(html: string, provider: PriceProviderId, providerLabel = providerLabels[provider]): PriceOffer[] {
  const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)]
    .map((match) => match[1])
    .filter((script) => {
      const lowered = script.toLowerCase();
      return lowered.includes("price") || lowered.includes("mrp") || lowered.includes("product");
    });
  const candidates: PriceOffer[] = [];
  const now = new Date().toISOString();

  function collectProducts(parsed: unknown) {
    walkObjects(parsed, (record) => {
      const name = String(
        record.name ?? record.productName ?? record.desc ?? record.description ?? record.title ?? "",
      ).trim();
      const sellingPrice = parseMoney(record.sellingPrice ?? record.salePrice ?? record.sp ?? record.price);
      if (!name || !sellingPrice) return;
      candidates.push(addUnitPrice({
        provider,
        providerLabel,
        productName: name,
        brand: typeof record.brand === "string" ? record.brand : undefined,
        packSize: typeof record.packSize === "string" ? record.packSize : extractPackSize(name),
        mrp: parseMoney(record.mrp ?? record.maximumRetailPrice),
        sellingPrice,
        currency: "INR",
        availability: String(record.availability ?? "").toLowerCase().includes("out")
          ? "out_of_stock"
          : "unknown",
        productUrl: typeof record.url === "string" ? record.url : undefined,
        imageUrl: typeof record.image === "string" ? record.image : undefined,
        confidence: 0.7,
        lastCheckedAt: now,
        source: "live",
      }));
    });
  }

  for (const script of scripts) {
    const parsedScript = tryJsonParse(script.trim());
    if (parsedScript) {
      collectProducts(parsedScript);
      continue;
    }

    const jsonBlocks = [
      ...script.matchAll(/({[\s\S]*?})/g),
    ].map((match) => match[1]).slice(0, 100);
    for (const block of jsonBlocks) {
      const parsed = tryJsonParse(block);
      if (!parsed) continue;
      collectProducts(parsed);
    }
  }

  return dedupeOffers(candidates);
}

export function dedupeOffers(offers: PriceOffer[]) {
  const seen = new Set<string>();
  const unique: PriceOffer[] = [];
  for (const offer of offers) {
    const key = `${offer.provider}|${normalizeQuery(offer.productName)}|${offer.packSize ?? ""}|${offer.sellingPrice}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(offer);
  }
  return unique;
}

async function bigBasketSearch(input: PriceSearchInput, fetcher: FetchLike): Promise<PriceOffer[]> {
  const url = `https://www.bigbasket.com/ps/?q=${encodeURIComponent(input.query)}`;
  const response = await fetcher(url, {
    headers: {
      "accept": "text/html,application/xhtml+xml",
      "user-agent": "CartSensePriceBot/0.1 (+https://cartsense.app; price comparison for user-requested searches)",
    },
  });
  if (!response.ok) throw new Error(`BigBasket returned HTTP ${response.status}`);
  const html = await response.text();
  return parseEmbeddedProductOffers(html, "bigbasket", providerLabels.bigbasket)
    .map((offer) => ({ ...offer, confidence: Number((offer.confidence * resultScore(input.query, offer.productName)).toFixed(2)) }))
    .filter((offer) => offer.confidence >= 0.35)
    .sort((a, b) => b.confidence - a.confidence || a.sellingPrice - b.sellingPrice)
    .slice(0, input.limit ?? 12);
}

async function providerSearch(provider: PriceProviderId, input: PriceSearchInput, fetcher: FetchLike): Promise<PriceOffer[]> {
  if (provider === "receipt" || provider === "shelf") {
    return searchMemoryPrices(input.query, input.limit ?? 12)
      .filter((event) => event.source === provider)
      .map((event) => addUnitPrice({
        provider,
        providerLabel: providerLabels[provider],
        productName: event.productName,
        brand: event.brand,
        mrp: event.mrp,
        sellingPrice: event.sellingPrice,
        currency: "INR",
        availability: "unknown",
        confidence: event.confidence,
        lastCheckedAt: event.uploadedAt,
        source: "cache",
      }));
  }
  if (provider === "demo") return demoSearch(input);
  if (provider === "bigbasket") return bigBasketSearch(input, fetcher);
  return [];
}

export async function searchPrices(rawInput: unknown, fetcher: FetchLike = fetch): Promise<PriceSearchResponse> {
  const input = normalizePriceSearchInput(rawInput);
  const providers = input.providers ?? ["demo", "bigbasket"];
  const cacheKey = JSON.stringify({ ...input, query: normalizeQuery(input.query), providers: [...providers].sort() });
  const cached = cache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) {
    return {
      ...cached.response,
      cached: true,
      offers: cached.response.offers.map((offer) => ({ ...offer, source: "cache" })),
    };
  }

  const warnings: string[] = [];
  const offers: PriceOffer[] = [];
  for (const provider of providers) {
    if (!supportedProviders.includes(provider)) {
      warnings.push(`${providerLabels[provider]} live lookup is not enabled yet.`);
      continue;
    }
    try {
      offers.push(...await providerSearch(provider, input, fetcher));
    } catch (error) {
      warnings.push(`${providerLabels[provider]} lookup failed: ${error instanceof Error ? error.message : "unknown error"}.`);
    }
  }

  const response: PriceSearchResponse = {
    query: input.query,
    normalizedQuery: normalizeQuery(input.query),
    pincode: input.pincode,
    providers,
    offers: dedupeOffers(offers)
      .sort((a, b) => a.sellingPrice - b.sellingPrice)
      .slice(0, input.limit ?? 12),
    warnings,
    cached: false,
  };
  cache.set(cacheKey, { expiresAt: Date.now() + cacheTtlMs, response });
  return response;
}
