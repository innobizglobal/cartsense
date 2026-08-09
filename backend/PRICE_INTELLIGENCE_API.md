# CartSense Price Intelligence API

Host this backend beside the CartSense AI receipt endpoint. The mobile app calls
it when the user wants "Better prices nearby" or online price comparison.

## Endpoint

`POST /api/price/search`

```json
{
  "query": "tetley tea",
  "pincode": "500037",
  "providers": ["demo", "bigbasket"],
  "limit": 12
}
```

Response:

```json
{
  "query": "tetley tea",
  "normalizedQuery": "tetley tea",
  "pincode": "500037",
  "providers": ["demo", "bigbasket"],
  "offers": [
    {
      "provider": "demo",
      "providerLabel": "CartSense demo prices",
      "productName": "Tetley Classic Tea 250g",
      "brand": "Tetley",
      "packSize": "250g",
      "mrp": 180,
      "sellingPrice": 165,
      "currency": "INR",
      "availability": "in_stock",
      "unitPrice": 660,
      "unit": "kg",
      "confidence": 0.98,
      "lastCheckedAt": "2026-08-09T00:00:00.000Z",
      "source": "demo"
    }
  ],
  "warnings": [],
  "cached": false
}
```

`GET /api/price/search?q=tea&pincode=500037&providers=demo,bigbasket` is also
supported for simple testing.

## Provider strategy

- `demo`: stable test catalog so the app can integrate and QA immediately.
- `bigbasket`: best-effort public web lookup. This may break if BigBasket changes
  page structure or blocks automated access.
- `jiomart`, `swiggy_instamart`, `blinkit`, `zepto`: API contract reserved, but
  live adapters are intentionally disabled until provider access/terms are
  confirmed.

## Hostinger deployment note

Use Hostinger's Node.js hosting or VPS. Shared PHP-only hosting will not run this
Next/Node backend directly. If the account is PHP-only, create a small VPS or
Hostinger Node.js app for the API and point a subdomain such as:

`https://price-api.cartsense.in/api/price/search`

## Safety rules

- Do not scrape user accounts or collect grocery-app passwords.
- Cache results and rate-limit requests.
- Show `lastCheckedAt` in the app because grocery prices change quickly.
- Keep receipt/shelf-photo price history as the reliable fallback.
