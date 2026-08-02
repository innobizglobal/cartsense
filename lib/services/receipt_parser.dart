import 'dart:io';
import 'package:flutter/services.dart';
import '../models/receipt.dart';
import 'receipt_text_parser.dart';

class ReceiptParser {
  ReceiptParser({ReceiptTextParser? textParser})
      : textParser = textParser ?? const ReceiptTextParser();

  final ReceiptTextParser textParser;
  static const _ocrChannel = MethodChannel('cartsense/receipt_ocr');

  Future<Receipt> parse(File image) async {
    final recognizedText =
        await _ocrChannel.invokeMethod<String>('recognizeReceipt', {
              'path': image.path,
            }) ??
            '';
    if (recognizedText.trim().isEmpty) {
      throw const FormatException(
        'No text was found. Retake the photo in bright light and keep the whole bill inside the frame.',
      );
    }
    final receipt = textParser.parse(
      recognizedText,
      imagePath: image.path,
    );
    if (receipt.items.isEmpty) {
      throw const FormatException(
        'Text was found, but no grocery items could be identified. Try a clearer, straighter photo.',
      );
    }
    return receipt;
  }
}
