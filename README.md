# CartSense Lite Mobile

Android-first Flutter application for scanning, reviewing, saving and exporting
supermarket receipts.

## Current checkpoint

- Private on-device text recognition for camera and gallery receipts
- Automatic store, date, product, quantity, price, discount and total extraction
- Editable itemised receipt
- Editable store, purchase date and printed total
- Low-confidence review state
- Quantity, discount and total reconciliation
- Searchable on-device receipt history with confirmed deletion
- Excel-compatible CSV share/export
- Demo bill works without any cloud configuration
- Receipt images and recognized text are not uploaded to a CartSense server

## Run

```bash
flutter create --platforms=android --org com.innobizglobal .
flutter pub get
flutter test
flutter run
```

## Build Android APK

```bash
flutter build apk --release
```

The first on-device scan can take a few seconds while Android initializes the
text-recognition engine. Accuracy depends on lighting, focus and keeping the
full receipt straight inside the photo.

The included GitHub Actions workflow tests the project and generates the release
APK. Run **Test and build Android APK** from the repository's Actions tab and
download the `CartSense-Android` artifact.
