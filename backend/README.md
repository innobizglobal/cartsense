# CartSense AI Receipt Service

Server-side receipt recognition for CartSense Lite. The Android app uploads a
receipt photo after explicit consent. The service sends the image to the
OpenAI Responses API with a strict receipt schema, removes administrative and
payment lines, validates item counts and arithmetic, and returns structured
JSON. Images are processed in memory and are not persisted by this service.

The OpenAI credential is supplied only through protected hosted environment
storage. A D1 counter applies a daily limit to hashed device/IP combinations.

## Price Intelligence API

CartSense also includes `/api/price/search`, a Hostinger-ready price lookup
endpoint for the app's "Better prices nearby" workflow. It normalizes grocery
searches, returns MRP/selling-price/pack-size data, caches results, and supports
pluggable providers.

Version 1 enables:

- `demo`: stable test catalog for mobile integration and QA.
- `bigbasket`: best-effort public web lookup.

Other providers (`JioMart`, `Swiggy Instamart`, `Blinkit`, `Zepto`) are reserved
in the API contract but intentionally disabled until access/terms are confirmed.
See `PRICE_INTELLIGENCE_API.md` for request/response examples and Hostinger
deployment notes.

## Checks

- `npm test` builds the worker and runs the parser/security regression tests.
- `npm run lint` checks the TypeScript source.
- `npm run db:generate` refreshes D1 migrations after schema changes.
