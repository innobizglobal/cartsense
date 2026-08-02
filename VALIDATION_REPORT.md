# CartSense Lite Mobile v0.1.0 — Validation Report

Status: **Source-complete; APK build pending**

## Implemented

- Flutter Android-first application architecture
- Camera and gallery receipt capture
- Editable itemised bill
- Quantity, unit price, discount and line-total calculations
- Printed-total reconciliation with a ₹0.05 tolerance
- Low-confidence review highlighting
- Add missing items
- On-device receipt persistence
- Excel-compatible CSV export through the Android share sheet
- Offline demo receipt with reconciled arithmetic
- Secure live-parser contract using a build-time server URL; no AI key is
  embedded in the app
- Automated arithmetic and confidence tests
- GitHub Actions release-APK workflow

## Verification performed here

- All declared Dart source and configuration files are present.
- No API key or Google credential is present in the mobile project.
- Demo arithmetic was independently recomputed: ₹1,488.50.
- Source scan found no TODO/FIXME placeholders in product logic.

## Verification not performed here

Flutter and the Android SDK are not installed in this execution environment, so
`flutter analyze`, `flutter test`, emulator/device testing and release APK
compilation could not be run here. The included workflow performs these steps
in a Flutter-capable build environment.

Live receipt extraction is intentionally not claimed as complete. It requires a
secure parser service URL and must never place the Gemini API key inside the
mobile package.

