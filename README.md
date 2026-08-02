# CartSense Lite Mobile

Android-first Flutter application for scanning, reviewing, saving and exporting
supermarket receipts.

## Current checkpoint

- Native camera and gallery entry points
- Editable itemised receipt
- Low-confidence review state
- Quantity, discount and total reconciliation
- On-device receipt history
- Excel-compatible CSV share/export
- Demo bill works without any cloud configuration
- Live parsing uses a server endpoint supplied at build time; no AI secret is
  embedded in the application

## Run

```bash
flutter create --platforms=android --org com.innobizglobal .
flutter pub get
flutter test
flutter run
```

## Build Android APK

```bash
flutter build apk --release \
  --dart-define=PARSER_URL=https://your-secure-parser.example/parse
```

Without `PARSER_URL`, camera/gallery capture remains available and the app
explains that live AI reading is not connected. The demo, editing, saving and
export flows remain usable.

The included GitHub Actions workflow can generate the release APK without
installing Flutter locally. Run **Build Android APK** from the repository's
Actions tab and download the `CartSense-Lite-Android` artifact.
