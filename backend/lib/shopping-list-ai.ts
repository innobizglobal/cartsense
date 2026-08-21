const categories = [
  "Fruit & vegetables",
  "Dairy & chilled",
  "Cooking oils",
  "Tea & coffee",
  "Pantry staples",
  "Beverages",
  "Snacks & sweets",
  "Breakfast & bakery",
  "Frozen & ready foods",
  "Household",
  "Personal care",
  "Sanitary care",
  "Baby care",
  "Other",
] as const;

export const shoppingListJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["items", "warnings"],
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "originalText",
          "name",
          "quantity",
          "unitLabel",
          "language",
          "category",
          "confidence",
        ],
        properties: {
          originalText: { type: "string" },
          name: { type: "string" },
          quantity: { type: "number" },
          unitLabel: { type: "string" },
          language: { type: "string" },
          category: { type: "string", enum: categories },
          confidence: { type: "number", minimum: 0, maximum: 1 },
        },
      },
    },
    warnings: { type: "array", items: { type: "string" } },
  },
} as const;

export const shoppingListPrompt = `You are reading a handwritten household grocery shopping list.

Return only structured data.

Rules:
- Read English, Telugu, Hindi, and mixed-language handwritten grocery lists.
- Ignore headings, dates, phone numbers, doodles, totals, prices, and non-grocery notes unless they are clearly a shopping item.
- Each line, comma-separated phrase, bullet, or numbered phrase may be one item.
- Translate product names to simple English product names for the name field, while preserving the exact visible phrase in originalText.
- Keep useful product words. For example: "పాలు" -> "milk", "चाय" -> "tea", "ఉప్పు" -> "salt", "साबुन" -> "soap".
- Normalize quantities: if quantity is missing use 1. "dozen" means 12. "half kg" means 0.5 with unitLabel "kg". "packet", "bottle", "kg", "g", "litre", "ml", "dozen" should be kept in unitLabel.
- Do not invent brand names. If the paper says a generic item like paste, return "toothpaste"; the mobile app may match it to the user's previous brand.
- Classify each product into exactly one listed category. Use Other only when it cannot reasonably fit another category.
- Sanitary pads and brands such as Whisper belong to Sanitary care. Tea belongs to Tea & coffee. Edible oil belongs to Cooking oils. Soaps/detergents/cleaning items belong to Household unless clearly personal care.
- If handwriting is unclear, return your best reading with lower confidence and add a warning.
- If the same item appears twice, merge it only when it is clearly the same product and same unit.`;

type UnknownRecord = Record<string, unknown>;

function finiteNumber(value: unknown, fallback = 1) {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : fallback;
}

export function normalizeShoppingList(raw: UnknownRecord) {
  const rawItems = Array.isArray(raw.items) ? raw.items : [];
  const seen = new Map<string, {
    originalText: string;
    name: string;
    quantity: number;
    unitLabel: string;
    language: string;
    category: string;
    confidence: number;
  }>();

  for (const value of rawItems) {
    if (!value || typeof value !== "object") continue;
    const item = value as UnknownRecord;
    const name = String(item.name ?? "").trim();
    if (name.length < 2) continue;
    const quantity = Math.min(999, Math.max(0.01, finiteNumber(item.quantity)));
    const unitLabel = String(item.unitLabel ?? "").trim().slice(0, 24);
    const key = `${name.toLowerCase()}|${unitLabel.toLowerCase()}`;
    const normalized = {
      originalText: String(item.originalText ?? name).trim().slice(0, 100),
      name: name.slice(0, 80),
      quantity,
      unitLabel,
      language: String(item.language ?? "unknown").trim().slice(0, 24) || "unknown",
      category: categories.includes(String(item.category) as typeof categories[number])
        ? String(item.category)
        : "Other",
      confidence: Math.min(1, Math.max(0, finiteNumber(item.confidence, 0.5))),
    };
    const existing = seen.get(key);
    if (existing) {
      existing.quantity = Math.min(999, existing.quantity + normalized.quantity);
      existing.confidence = Math.min(existing.confidence, normalized.confidence);
      if (!existing.originalText.includes(normalized.originalText)) {
        existing.originalText = `${existing.originalText}, ${normalized.originalText}`.slice(0, 100);
      }
    } else {
      seen.set(key, normalized);
    }
  }

  const warnings = Array.isArray(raw.warnings)
    ? raw.warnings.map(String).map((value) => value.trim()).filter(Boolean).slice(0, 8)
    : [];

  return {
    items: [...seen.values()].slice(0, 80),
    warnings: [...new Set(warnings)],
  };
}
