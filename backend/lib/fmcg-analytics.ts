export interface AnonymousPriceItemInput {
  productName?: unknown;
  name?: unknown;
  quantity?: unknown;
  unitPrice?: unknown;
  sellingPrice?: unknown;
  mrp?: unknown;
  category?: unknown;
  confidence?: unknown;
}

export interface AnonymousReceiptIngestInput {
  receiptId?: unknown;
  storeName?: unknown;
  purchasedAt?: unknown;
  pincode?: unknown;
  city?: unknown;
  items?: unknown;
}

export interface AnonymousProductEvent {
  eventId: string;
  receiptHash: string;
  source: "receipt" | "shelf";
  productName: string;
  normalizedProductName: string;
  brand: string;
  category: string;
  storeName: string;
  month: string;
  quantity: number;
  unitPrice: number;
  sellingPrice: number;
  mrp?: number;
  lineTotal: number;
  confidence: number;
  uploadedAt: string;
  pincode?: string;
  city?: string;
}

export interface IngestResult {
  status: "ok";
  anonymous: true;
  storedItems: number;
  skippedItems: number;
  month?: string;
}

const memoryEvents: AnonymousProductEvent[] = [];
const maxMemoryEvents = 25_000;

const genericBrandWords = new Set([
  "fresh",
  "classic",
  "super",
  "premium",
  "organic",
  "new",
  "best",
  "gold",
  "refined",
  "pure",
]);

export function normalizeProductName(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\b(gm|gms|gram|grams)\b/g, "g")
    .replace(/\b(litre|liter|litres|liters)\b/g, "l")
    .replace(/\s+/g, " ")
    .trim();
}

function cleanText(value: unknown, fallback = "") {
  return String(value ?? fallback)
    .replace(/[^\p{L}\p{N}\s&.+/-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 120);
}

function money(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Number(value.toFixed(2));
  }
  if (typeof value !== "string") return 0;
  const match = value.replace(/,/g, "").match(/\d+(?:\.\d{1,2})?/);
  if (!match) return 0;
  const parsed = Number.parseFloat(match[0]);
  return Number.isFinite(parsed) ? Number(parsed.toFixed(2)) : 0;
}

function quantity(value: unknown) {
  const parsed = typeof value === "number" ? value : Number.parseFloat(String(value ?? "1"));
  if (!Number.isFinite(parsed) || parsed <= 0) return 1;
  return Number(Math.min(parsed, 999).toFixed(3));
}

function confidence(value: unknown) {
  const parsed = typeof value === "number" ? value : Number.parseFloat(String(value ?? ".8"));
  if (!Number.isFinite(parsed)) return 0.8;
  return Number(Math.max(0, Math.min(1, parsed)).toFixed(2));
}

function monthFrom(value: unknown) {
  const date = new Date(String(value ?? ""));
  const usable = Number.isFinite(date.getTime()) ? date : new Date();
  return `${usable.getUTCFullYear()}-${String(usable.getUTCMonth() + 1).padStart(2, "0")}`;
}

function simpleHash(value: string) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function inferBrand(productName: string) {
  const words = productName
    .split(/\s+/)
    .map((word) => word.replace(/[^a-z0-9]/gi, ""))
    .filter((word) => word.length > 1 && !/^\d/.test(word));
  const firstUseful = words.find((word) => !genericBrandWords.has(word.toLowerCase()));
  return firstUseful ?? "Unknown";
}

function sanitizePincode(value: unknown) {
  const pincode = String(value ?? "").replace(/\D/g, "").slice(0, 6);
  return pincode.length === 6 ? pincode : undefined;
}

export function normalizeAnonymousReceiptIngest(
  raw: AnonymousReceiptIngestInput,
  source: "receipt" | "shelf" = "receipt",
): { events: AnonymousProductEvent[]; skippedItems: number; month: string } {
  const storeName = cleanText(raw.storeName, source === "shelf" ? "Shelf" : "Unknown store");
  const month = monthFrom(raw.purchasedAt);
  const receiptHash = simpleHash(`${source}|${raw.receiptId ?? ""}|${storeName}|${month}`);
  const pincode = sanitizePincode(raw.pincode);
  const city = cleanText(raw.city).slice(0, 60) || undefined;
  const items = Array.isArray(raw.items) ? raw.items : [];
  const events: AnonymousProductEvent[] = [];
  let skippedItems = 0;

  for (const item of items) {
    const record = typeof item === "object" && item !== null ? item as AnonymousPriceItemInput : {};
    const productName = cleanText(record.productName ?? record.name);
    const normalizedProduct = normalizeProductName(productName);
    const unitPrice = money(record.unitPrice);
    const sellingPrice = money(record.sellingPrice) || unitPrice;
    const qty = quantity(record.quantity);
    if (normalizedProduct.length < 2 || sellingPrice <= 0) {
      skippedItems += 1;
      continue;
    }
    const category = cleanText(record.category, "Other") || "Other";
    events.push({
      eventId: simpleHash(`${receiptHash}|${normalizedProduct}|${events.length}|${sellingPrice}`),
      receiptHash,
      source,
      productName,
      normalizedProductName: normalizedProduct,
      brand: inferBrand(productName),
      category,
      storeName,
      month,
      quantity: qty,
      unitPrice: unitPrice > 0 ? unitPrice : sellingPrice,
      sellingPrice,
      mrp: money(record.mrp) || undefined,
      lineTotal: Number((sellingPrice * qty).toFixed(2)),
      confidence: confidence(record.confidence),
      uploadedAt: new Date().toISOString(),
      pincode,
      city,
    });
  }

  return { events, skippedItems, month };
}

export function ingestAnonymousReceipt(
  raw: AnonymousReceiptIngestInput,
  source: "receipt" | "shelf" = "receipt",
): IngestResult {
  const normalized = normalizeAnonymousReceiptIngest(raw, source);
  const existingKeys = new Set(memoryEvents.map((event) => event.eventId));
  const freshEvents = normalized.events.filter((event) => !existingKeys.has(event.eventId));
  memoryEvents.push(...freshEvents);
  if (memoryEvents.length > maxMemoryEvents) {
    memoryEvents.splice(0, memoryEvents.length - maxMemoryEvents);
  }
  return {
    status: "ok",
    anonymous: true,
    storedItems: freshEvents.length,
    skippedItems: normalized.skippedItems,
    month: normalized.month,
  };
}

export function getAnonymousEvents() {
  return [...memoryEvents];
}

function addAggregate<T extends { spend: number; quantity: number; purchases: number }>(
  map: Map<string, T>,
  key: string,
  create: () => T,
  event: AnonymousProductEvent,
) {
  const current = map.get(key) ?? create();
  current.spend = Number((current.spend + event.lineTotal).toFixed(2));
  current.quantity = Number((current.quantity + event.quantity).toFixed(3));
  current.purchases += 1;
  map.set(key, current);
}

export function buildFmcgAnalyticsSummary(params: { month?: string; limit?: number } = {}) {
  const limit = Math.min(50, Math.max(1, Number(params.limit ?? 10)));
  const month = params.month;
  const events = memoryEvents.filter((event) => !month || event.month === month);
  const receiptCount = new Set(events.map((event) => event.receiptHash)).size;
  const totalSpend = events.reduce((sum, event) => sum + event.lineTotal, 0);

  const categories = new Map<string, { category: string; spend: number; quantity: number; purchases: number }>();
  const products = new Map<string, { productName: string; category: string; brand: string; spend: number; quantity: number; purchases: number; averageUnitPrice: number }>();
  const brands = new Map<string, { brand: string; spend: number; quantity: number; purchases: number }>();
  const stores = new Map<string, { storeName: string; spend: number; quantity: number; purchases: number }>();
  const months = new Map<string, { month: string; spend: number; quantity: number; purchases: number }>();

  for (const event of events) {
    addAggregate(categories, event.category, () => ({ category: event.category, spend: 0, quantity: 0, purchases: 0 }), event);
    addAggregate(brands, event.brand, () => ({ brand: event.brand, spend: 0, quantity: 0, purchases: 0 }), event);
    addAggregate(stores, event.storeName, () => ({ storeName: event.storeName, spend: 0, quantity: 0, purchases: 0 }), event);
    addAggregate(months, event.month, () => ({ month: event.month, spend: 0, quantity: 0, purchases: 0 }), event);

    addAggregate(products, event.normalizedProductName, () => ({
      productName: event.productName,
      category: event.category,
      brand: event.brand,
      spend: 0,
      quantity: 0,
      purchases: 0,
      averageUnitPrice: 0,
    }), event);
  }

  const topProducts = [...products.values()]
    .map((item) => ({
      ...item,
      averageUnitPrice: Number((item.spend / Math.max(item.quantity, 1)).toFixed(2)),
    }))
    .sort((a, b) => b.spend - a.spend)
    .slice(0, limit);

  return {
    status: "ok",
    anonymous: true,
    privacy:
      "Aggregated FMCG analytics only. No names, phone numbers, emails, receipt images, payment details or exact addresses are stored.",
    filters: { month: month ?? "all", limit },
    totals: {
      receipts: receiptCount,
      productRows: events.length,
      totalSpend: Number(totalSpend.toFixed(2)),
      averageBasket: receiptCount ? Number((totalSpend / receiptCount).toFixed(2)) : 0,
    },
    categorySpend: [...categories.values()].sort((a, b) => b.spend - a.spend).slice(0, limit),
    topProducts,
    brandSpend: [...brands.values()].sort((a, b) => b.spend - a.spend).slice(0, limit),
    storeSpend: [...stores.values()].sort((a, b) => b.spend - a.spend).slice(0, limit),
    monthlyTrend: [...months.values()].sort((a, b) => a.month.localeCompare(b.month)),
  };
}

export function searchMemoryPrices(query: string, limit = 12) {
  const normalized = normalizeProductName(query);
  if (normalized.length < 2) return [];
  const candidates = memoryEvents
    .filter((event) => event.normalizedProductName.includes(normalized))
    .sort((a, b) => a.sellingPrice - b.sellingPrice || b.uploadedAt.localeCompare(a.uploadedAt));
  const seen = new Set<string>();
  return candidates
    .filter((event) => {
      const key = `${event.storeName}|${event.normalizedProductName}|${event.sellingPrice}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, limit);
}

export function compareCartWithMemory(raw: unknown) {
  const input = typeof raw === "object" && raw !== null ? raw as Record<string, unknown> : {};
  const budget = money(input.budget);
  const items = Array.isArray(input.items) ? input.items : [];
  const comparisons = items.map((item) => {
    const record = typeof item === "object" && item !== null ? item as Record<string, unknown> : {};
    const name = cleanText(record.name ?? record.productName);
    const qty = quantity(record.quantity);
    const expectedUnitPrice = money(record.expectedUnitPrice);
    const matches = searchMemoryPrices(name, 5);
    const best = matches[0];
    const bestUnitPrice = best?.sellingPrice ?? expectedUnitPrice;
    return {
      name,
      quantity: qty,
      category: cleanText(record.category, "Other"),
      expectedUnitPrice,
      bestUnitPrice,
      bestStore: best?.storeName ?? "",
      estimatedTotal: Number((qty * expectedUnitPrice).toFixed(2)),
      bestTotal: Number((qty * bestUnitPrice).toFixed(2)),
      savesAbout: expectedUnitPrice > bestUnitPrice
        ? Number((qty * (expectedUnitPrice - bestUnitPrice)).toFixed(2))
        : 0,
      matchedPrices: matches.length,
    };
  }).filter((item) => item.name.length > 0);

  const estimatedTotal = comparisons.reduce((sum, item) => sum + item.estimatedTotal, 0);
  const bestTotal = comparisons.reduce((sum, item) => sum + item.bestTotal, 0);
  const removalSuggestions = [...comparisons]
    .filter((item) => item.estimatedTotal > 0)
    .sort((a, b) => b.estimatedTotal - a.estimatedTotal)
    .slice(0, 5)
    .map((item) => ({
      name: item.name,
      removeAmount: item.estimatedTotal,
      reason: budget > 0 && estimatedTotal > budget
        ? "Remove this to move closer to budget."
        : "Highest planned basket value.",
    }));

  return {
    status: "ok",
    anonymous: true,
    estimatedTotal: Number(estimatedTotal.toFixed(2)),
    bestTotal: Number(bestTotal.toFixed(2)),
    possibleSaving: Number((estimatedTotal - bestTotal).toFixed(2)),
    budget,
    budgetGap: budget > 0 ? Number((estimatedTotal - budget).toFixed(2)) : 0,
    comparisons,
    removalSuggestions,
  };
}
