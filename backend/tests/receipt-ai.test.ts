import assert from "node:assert/strict";
import test from "node:test";
import { normalizeReceipt } from "../lib/receipt-ai";
import { GET as health } from "../app/api/health/route";

test("removes payment metadata and refuses a false total match", () => {
  const receipt = normalizeReceipt({
    store: "D Mart Balanagar",
    purchasedAt: "2026-08-02",
    currency: "INR",
    printedTotal: 5638.2,
    printedItemCount: 23,
    printedQuantityTotal: 28,
    taxTotal: 377.14,
    billDiscount: 0,
    otherCharges: 0,
    overallConfidence: 0.81,
    warnings: [],
    items: [
      { name: "HERITAGE PANEER", quantity: 1, unitPrice: 90, lineTotal: 90, discount: 0, confidence: 0.96 },
      { name: "Amount Received From Customer", quantity: 1, unitPrice: 5638.2, lineTotal: 5638.2, discount: 0, confidence: 0.5 },
    ],
  });

  assert.equal(receipt.printedTotal, 5638.2);
  assert.equal(receipt.items.length, 1);
  assert.equal(receipt.items[0].name, "HERITAGE PANEER");
  assert.match(receipt.warnings.join(" "), /removed/i);
  assert.match(receipt.warnings.join(" "), /Printed item count is 23/i);
  assert.match(receipt.warnings.join(" "), /differs from the printed total/i);
});

test("health route returns service status", async () => {
  const response = await health();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    service: "CartSense AI Receipt Service",
    status: "ok",
  });
});
