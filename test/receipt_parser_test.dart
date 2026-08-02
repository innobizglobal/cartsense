import 'dart:io';

import 'package:cartsense_lite/services/receipt_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cartsense/receipt_ocr');

  test('passes the image path to the native Latin recognizer', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return '''
FRESH MART
02/08/2026
Milk 2 30.00 60.00
TOTAL 60.00
''';
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final receipt = await ReceiptParser().parse(File('/receipt.jpg'));

    expect(receivedCall?.method, 'recognizeReceipt');
    expect(receivedCall?.arguments, {'path': '/receipt.jpg'});
    expect(receipt.store, 'Fresh Mart');
    expect(receipt.items.single.name, 'Milk');
    expect(receipt.reconciled, isTrue);
  });
}
