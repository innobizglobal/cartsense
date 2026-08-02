import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/receipt.dart';
import 'receipt_text_parser.dart';

class ReceiptParser {
  ReceiptParser({ReceiptTextParser? textParser})
      : textParser = textParser ?? const ReceiptTextParser();

  final ReceiptTextParser textParser;

  Future<Receipt> parse(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFile(image));
      if (recognized.text.trim().isEmpty) {
        throw const FormatException(
          'No text was found. Retake the photo in bright light and keep the whole bill inside the frame.',
        );
      }
      final receipt = textParser.parse(
        recognized.text,
        imagePath: image.path,
      );
      if (receipt.items.isEmpty) {
        throw const FormatException(
          'Text was found, but no grocery items could be identified. Try a clearer, straighter photo.',
        );
      }
      return receipt;
    } finally {
      await recognizer.close();
    }
  }
}
