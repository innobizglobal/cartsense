export const receiptJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "store",
    "purchasedAt",
    "currency",
    "printedTotal",
    "printedItemCount",
    "printedQuantityTotal",
    "taxTotal",
    "billDiscount",
    "otherCharges",
    "items",
    "overallConfidence",
    "warnings",
  ],
  properties: {
    store: { type: "string" },
    purchasedAt: { type: ["string", "null"] },
    currency: { type: "string" },
    printedTotal: { type: "number" },
    printedItemCount: { type: ["integer", "null"] },
    printedQuantityTotal: { type: ["number", "null"] },
    taxTotal: { type: "number" },
    billDiscount: { type: "number" },
    otherCharges: { type: "number" },
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "name",
          "quantity",
          "unitPrice",
          "lineTotal",
          "discount",
          "confidence",
        ],
        properties: {
          name: { type: "string" },
          quantity: { type: "number" },
          unitPrice: { type: "number" },
          lineTotal: { type: "number" },
          discount: { type: "number" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
        },
      },
    },
    overallConfidence: { type: "number", minimum: 0, maximum: 1 },
    warnings: { type: "array", items: { type: "string" } },
  },
} as const;

export const receiptPrompt = `You are an expert grocery receipt analyst. Read the receipt image itself, including its table geometry. Return only the requested structured data.

Rules:
- Extract product rows only. Never put headers, addresses, survey text, GST summaries, tax rows, payment methods, "amount received from customer", change, savings messages, bill numbers, barcodes, or totals into items.
- Preserve visible product names. Correct obvious OCR letter mistakes only when the printed word is visually supported; do not invent brands or products.
- Use the quantity, unit rate and line value from the same printed row. If a receipt prints tax separately, lineTotal is the pre-tax line value and taxTotal is the separately added tax. If tax is already included in item values, set taxTotal to 0.
- printedTotal is the final amount payable/received, not a subtotal, tax-group amount, savings amount, or payment identifier.
- billDiscount is only a bill-level discount not already subtracted from item line totals. otherCharges contains separately added non-tax charges.
- Capture printed item count and total quantity when visible. Use null when not visible.
- Confidence must reflect image evidence. Folded, shadowed, stamped, blurred, clipped or ambiguous rows must have lower confidence and a concise warning.
- Check arithmetic: sum(items.lineTotal) + taxTotal + otherCharges - billDiscount should equal printedTotal when the receipt exposes all components. Report any mismatch in warnings.
- For Indian receipts use currency INR and ISO date YYYY-MM-DD when the date is readable.`;

const allowedImageTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

export async function imageType(file: File) {
  if (allowedImageTypes.has(file.type)) return file.type;
  const lower = file.name.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";

  const bytes = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return "image/webp";
  }
  return null;
}

type UnknownRecord = Record<string, unknown>;

const excludedItemText = /\b(amount\s+received|received\s+from|customer|payment|upi|cash|change|grand\s+total|sub\s*total|taxable|cgst|sgst|igst|gst\s+breakup|saved|survey|bill\s+no|invoice)\b/i;

function finiteNumber(value: unknown, fallback = 0) {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : fallback;
}

export function normalizeReceipt(raw: UnknownRecord) {
  const rawItems = Array.isArray(raw.items) ? raw.items : [];
  const items = rawItems
    .filter((value): value is UnknownRecord => !!value && typeof value === "object")
    .map((item) => ({
      name: String(item.name ?? "").trim(),
      quantity: Math.max(0, finiteNumber(item.quantity, 1)),
      unitPrice: Math.max(0, finiteNumber(item.unitPrice)),
      parsedLineTotal: Math.max(0, finiteNumber(item.lineTotal)),
      discount: Math.max(0, finiteNumber(item.discount)),
      confidence: Math.min(1, Math.max(0, finiteNumber(item.confidence, 0.5))),
    }))
    .filter((item) => item.name.length >= 2 && item.parsedLineTotal > 0 && !excludedItemText.test(item.name));

  const warnings = Array.isArray(raw.warnings)
    ? raw.warnings.map(String).map((value) => value.trim()).filter(Boolean).slice(0, 12)
    : [];
  if (items.length !== rawItems.length) {
    warnings.push("Administrative or payment lines were removed from the item list.");
  }

  const printedItemCount = raw.printedItemCount == null
    ? null
    : Math.max(0, Math.trunc(finiteNumber(raw.printedItemCount)));
  if (printedItemCount != null && printedItemCount !== items.length) {
    warnings.push(`Printed item count is ${printedItemCount}, but ${items.length} product rows were extracted.`);
  }

  const printedTotal = Math.max(0, finiteNumber(raw.printedTotal));
  const taxTotal = Math.max(0, finiteNumber(raw.taxTotal));
  const billDiscount = Math.max(0, finiteNumber(raw.billDiscount));
  const otherCharges = Math.max(0, finiteNumber(raw.otherCharges));
  const calculated = items.reduce((sum, item) => sum + item.parsedLineTotal, 0)
    + taxTotal + otherCharges - billDiscount;
  if (printedTotal > 0 && Math.abs(calculated - printedTotal) > 0.05) {
    warnings.push(`Extracted arithmetic differs from the printed total by ${Math.abs(calculated - printedTotal).toFixed(2)}.`);
  }

  return {
    id: crypto.randomUUID(),
    store: String(raw.store ?? "Scanned grocery bill").trim() || "Scanned grocery bill",
    purchasedAt: typeof raw.purchasedAt === "string" ? raw.purchasedAt : null,
    currency: String(raw.currency ?? "INR"),
    printedTotal,
    printedItemCount,
    printedQuantityTotal: raw.printedQuantityTotal == null
      ? null
      : Math.max(0, finiteNumber(raw.printedQuantityTotal)),
    taxTotal,
    billDiscount,
    otherCharges,
    items,
    overallConfidence: Math.min(1, Math.max(0, finiteNumber(raw.overallConfidence, 0.5))),
    warnings: [...new Set(warnings)],
    recognitionSource: "ai_enhanced",
  };
}

export function extractResponseText(payload: UnknownRecord) {
  const output = Array.isArray(payload.output) ? payload.output : [];
  for (const entry of output) {
    if (!entry || typeof entry !== "object") continue;
    const content = Array.isArray((entry as UnknownRecord).content)
      ? (entry as UnknownRecord).content as unknown[]
      : [];
    for (const part of content) {
      if (!part || typeof part !== "object") continue;
      const candidate = part as UnknownRecord;
      if (candidate.type === "output_text" && typeof candidate.text === "string") {
        return candidate.text;
      }
    }
  }
  throw new Error("The AI service returned no structured receipt data.");
}
