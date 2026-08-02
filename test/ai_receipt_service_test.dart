import 'dart:convert';
import 'dart:io';
import 'package:cartsense_lite/services/ai_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AI service uploads an image and decodes structured receipt data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}cartsense-ai-test.jpg',
    );
    await image.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    final client = MockClient((request) async {
      expect(request.url.path, '/api/receipt');
      expect(request.headers['x-cartsense-device'], isNotEmpty);
      expect(request.bodyBytes, isNotEmpty);
      expect(
        request.headers['content-type'],
        contains('multipart/form-data'),
      );
      expect(
        latin1.decode(request.bodyBytes),
        contains('content-type: image/jpeg'),
      );
      return http.Response(
        jsonEncode({
          'receipt': {
            'id': 'ai-test',
            'store': 'D Mart Balanagar',
            'purchasedAt': '2026-08-02',
            'items': [
              {
                'name': 'HERITAGE PANEER',
                'quantity': 1,
                'unitPrice': 90,
                'parsedLineTotal': 90,
                'discount': 0,
                'confidence': .95,
              },
            ],
            'printedTotal': 90,
            'printedItemCount': 1,
            'printedQuantityTotal': 1,
            'taxTotal': 0,
            'billDiscount': 0,
            'otherCharges': 0,
            'overallConfidence': .94,
            'warnings': [],
            'recognitionSource': 'ai_enhanced',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = AiReceiptService(
      client: client,
      endpoint: 'https://example.test/api/receipt',
    );
    final receipt = await service.parse(image);

    expect(receipt.store, 'D Mart Balanagar');
    expect(receipt.items.single.name, 'HERITAGE PANEER');
    expect(receipt.confidentlyReconciled, isTrue);
    expect(receipt.imagePath, image.path);
  });
}
