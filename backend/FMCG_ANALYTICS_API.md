# CartSense Anonymous FMCG Analytics API

CartSense stores only anonymous, aggregated grocery intelligence for FMCG use.

It does **not** store user name, phone, email, receipt image, payment reference,
UPI details, exact address, or raw personal identifiers.

## Anonymous receipt ingest

`POST /api/price/ingest/receipt`

The mobile app already calls this after a receipt is saved.

```json
{
  "receiptId": "local-device-receipt-id",
  "storeName": "DMart",
  "purchasedAt": "2026-08-11T12:00:00.000Z",
  "items": [
    {
      "productName": "Tata Tea Gold 500g",
      "quantity": 1,
      "unitPrice": 318,
      "sellingPrice": 318,
      "category": "Tea & coffee",
      "confidence": 0.98
    }
  ]
}
```

Response:

```json
{
  "status": "ok",
  "anonymous": true,
  "storedItems": 1,
  "skippedItems": 0,
  "month": "2026-08"
}
```

## Anonymous shelf-price ingest

`POST /api/price/ingest/shelf`

Used when a user scans a shelf price label.

## FMCG analytics summary

`GET /api/fmcg/analytics?month=2026-08&limit=10`

Returns:

- total anonymous receipts and product rows
- average basket value
- category spend
- top products
- brand spend
- store spend
- monthly trend

## Cart comparison from collected price memory

`POST /api/price/cart/compare`

Uses anonymous receipt/shelf prices to compare the planned cart and suggest
possible savings/removals before checkout.

## Current storage note

This build includes an in-process memory store so Hostinger/local deployments can
run immediately. The Drizzle table `anonymous_product_events` is also defined so
the same data model can be moved to persistent SQL storage for production FMCG
dashboards.
