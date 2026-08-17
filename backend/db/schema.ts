import { integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const scanUsage = sqliteTable(
  "scan_usage",
  {
    bucket: text("bucket").notNull(),
    clientHash: text("client_hash").notNull(),
    scanCount: integer("scan_count").notNull().default(0),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.bucket, table.clientHash] })],
);

export const anonymousProductEvents = sqliteTable(
  "anonymous_product_events",
  {
    eventId: text("event_id").notNull(),
    receiptHash: text("receipt_hash").notNull(),
    source: text("source").notNull(),
    productName: text("product_name").notNull(),
    normalizedProductName: text("normalized_product_name").notNull(),
    brand: text("brand").notNull(),
    category: text("category").notNull(),
    storeName: text("store_name").notNull(),
    month: text("month").notNull(),
    quantity: integer("quantity").notNull(),
    unitPricePaise: integer("unit_price_paise").notNull(),
    sellingPricePaise: integer("selling_price_paise").notNull(),
    mrpPaise: integer("mrp_paise"),
    lineTotalPaise: integer("line_total_paise").notNull(),
    confidencePct: integer("confidence_pct").notNull(),
    uploadedAt: text("uploaded_at").notNull(),
    pincode: text("pincode"),
    city: text("city"),
  },
  (table) => [primaryKey({ columns: [table.eventId] })],
);
