import assert from "node:assert/strict";
import test from "node:test";
import { imageType, normalizeReceipt, shouldAuditReceipt } from "../lib/receipt-ai";
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

test("recognizes Android uploads with a generic content type", async () => {
  const jpeg = new File(
    [new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10])],
    "blob",
    { type: "application/octet-stream" },
  );
  assert.equal(await imageType(jpeg), "image/jpeg");
});

test("requests an audit when extracted totals or counts disagree", () => {
  const receipt = normalizeReceipt({
    store: "Fresh Mart",
    purchasedAt: "2026-08-02",
    currency: "INR",
    printedTotal: 200,
    printedItemCount: 2,
    printedQuantityTotal: 2,
    taxTotal: 0,
    billDiscount: 0,
    otherCharges: 0,
    overallConfidence: 0.96,
    warnings: [],
    items: [
      { name: "Milk", quantity: 1, unitPrice: 80, lineTotal: 80, discount: 0, confidence: 0.95 },
    ],
  });

  assert.equal(shouldAuditReceipt(receipt), true);
});

test("keeps a high-confidence reconciled receipt on the fast path", () => {
  const receipt = normalizeReceipt({
    store: "Fresh Mart",
    purchasedAt: "2026-08-02",
    currency: "INR",
    printedTotal: 200,
    printedItemCount: 2,
    printedQuantityTotal: 2,
    taxTotal: 0,
    billDiscount: 0,
    otherCharges: 0,
    overallConfidence: 0.96,
    warnings: [],
    items: [
      { name: "Milk", quantity: 1, unitPrice: 80, lineTotal: 80, discount: 0, confidence: 0.95 },
      { name: "Rice", quantity: 1, unitPrice: 120, lineTotal: 120, discount: 0, confidence: 0.94 },
    ],
  });

  assert.equal(shouldAuditReceipt(receipt), false);
});

test("does not add GST twice when product values already equal the payable total", () => {
  const receipt = normalizeReceipt({
    store: "D-Mart",
    purchasedAt: "2026-08-02",
    currency: "INR",
    printedTotal: 200,
    printedItemCount: 2,
    printedQuantityTotal: 2,
    taxTotal: 20,
    billDiscount: 0,
    otherCharges: 0,
    overallConfidence: 0.96,
    warnings: [],
    items: [
      { name: "Milk", quantity: 1, unitPrice: 80, lineTotal: 80, discount: 0, confidence: 0.95 },
      { name: "Rice", quantity: 1, unitPrice: 120, lineTotal: 120, discount: 0, confidence: 0.94 },
    ],
  });

  assert.equal(receipt.taxTotal, 0);
  assert.match(receipt.warnings.join(" "), /not added twice/i);
  assert.doesNotMatch(receipt.warnings.join(" "), /differs from the printed total/i);
});
