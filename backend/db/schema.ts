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
