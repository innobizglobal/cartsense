# CartSense AI Receipt Service

Server-side receipt recognition for CartSense Lite. The Android app uploads a
receipt photo after explicit consent. The service sends the image to the
OpenAI Responses API with a strict receipt schema, removes administrative and
payment lines, validates item counts and arithmetic, and returns structured
JSON. Images are processed in memory and are not persisted by this service.

The OpenAI credential is supplied only through protected hosted environment
storage. A D1 counter applies a daily limit to hashed device/IP combinations.

## Checks

- `npm test` builds the worker and runs the parser/security regression tests.
- `npm run lint` checks the TypeScript source.
- `npm run db:generate` refreshes D1 migrations after schema changes.
