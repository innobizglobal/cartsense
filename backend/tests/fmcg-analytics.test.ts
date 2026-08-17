import assert from "node:assert/strict";
import test from "node:test";
import {
  buildFmcgAnalyticsSummary,
  compareCartWithMemory,
  ingestAnonymousReceipt,
  normalizeAnonymousReceiptIngest,
} from "../lib/fmcg-analytics";
import { searchPrices } from "../lib/price-intelligence";

test("normalizes anonymous receipt data without personal fields", () => {
  const normalized = normalizeAnonymousReceiptIngest({
    receiptId: "bill-123",
    storeName: "DMart Balanagar",
    purchasedAt: "2026-08-10T10:00:00.000Z",
    items: [
      {
        productName: "Tetley Classic Tea 250g",
        quantity: 2,
        unitPrice: 165,
        category: "Tea & coffee",
        confidence: 0.98,
      },
      { productName: "", sellingPrice: 20 },
    ],
  });

  assert.equal(normalized.events.length, 1);
  assert.equal(normalized.skippedItems, 1);
  assert.equal(normalized.month, "2026-08");
  assert.equal(normalized.events[0].category, "Tea & coffee");
  assert.equal(normalized.events[0].lineTotal, 330);
  assert.ok(!("email" in normalized.events[0]));
  assert.ok(!("phone" in normalized.events[0]));
});

test("ingests FMCG data and builds aggregate summary", () => {
  const result = ingestAnonymousReceipt({
    receiptId: "bill-analytics-1",
    storeName: "Reliance Smart",
    purchasedAt: "2026-08-11T12:00:00.000Z",
    items: [
      { productName: "Gold Drop Sunflower Oil 1L", quantity: 1, sellingPrice: 168, category: "Cooking oils" },
      { productName: "Whisper Choice Pads 20 pcs", quantity: 1, sellingPrice: 139, category: "Sanitary care" },
    ],
  });

  assert.equal(result.status, "ok");
  assert.equal(result.anonymous, true);
  assert.equal(result.storedItems, 2);

  const summary = buildFmcgAnalyticsSummary({ month: "2026-08", limit: 5 });
  assert.equal(summary.anonymous, true);
  assert.ok(summary.totals.productRows >= 2);
  assert.ok(summary.categorySpend.some((category) => category.category === "Cooking oils"));
  assert.ok(summary.topProducts.some((product) => product.productName.includes("Gold Drop")));
});

test("receipt memory powers cart comparison and price search", async () => {
  ingestAnonymousReceipt({
    receiptId: "bill-memory-1",
    storeName: "DMart",
    purchasedAt: "2026-08-11T12:00:00.000Z",
    items: [
      { productName: "Tata Tea Gold 500g", quantity: 1, sellingPrice: 318, category: "Tea & coffee" },
    ],
  });

  const comparison = compareCartWithMemory({
    budget: 400,
    items: [
      { name: "Tata Tea", quantity: 1, expectedUnitPrice: 340, category: "Tea & coffee" },
    ],
  });
  assert.equal(comparison.status, "ok");
  assert.ok(comparison.possibleSaving >= 22);
  assert.equal(comparison.comparisons[0].bestStore, "DMart");

  const prices = await searchPrices({ query: "Tata Tea", providers: ["receipt"], limit: 3 });
  assert.ok(prices.offers.some((offer) => offer.provider === "receipt"));
});
