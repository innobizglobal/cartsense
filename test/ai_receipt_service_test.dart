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

  test('AI service uploads ordered long receipt sections', () async {
    SharedPreferences.setMockInitialValues({});
    final first = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}cartsense-ai-long-1.jpg',
    );
    final second = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}cartsense-ai-long-2.jpg',
    );
    await first.writeAsBytes([1, 2, 3, 4]);
    await second.writeAsBytes([5, 6, 7, 8]);
    addTearDown(() async {
      if (await first.exists()) await first.delete();
      if (await second.exists()) await second.delete();
    });

    final client = MockClient((request) async {
      expect(request.headers['x-cartsense-receipt-parts'], '2');
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('receipt_part_1.jpg'));
      expect(body, contains('receipt_part_2.jpg'));
      return http.Response(
        jsonEncode({
          'receipt': {
            'id': 'ai-long-test',
            'store': 'Long Grocery Bill',
            'purchasedAt': '2026-08-02',
            'items': [
              {
                'name': 'TETLEY CLASSIC',
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
    final receipt = await service.parseImages([first, second]);

    expect(receipt.store, 'Long Grocery Bill');
    expect(receipt.items.single.name, 'TETLEY CLASSIC');
    expect(receipt.imagePath, first.path);
  });

  test('AI service uploads handwritten shopping list photos', () async {
    SharedPreferences.setMockInitialValues({});
    final image = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}cartsense-paper-list.jpg',
    );
    await image.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    final client = MockClient((request) async {
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('name="mode"'));
      expect(body, contains('shopping_list_photo'));
      expect(body, contains('name="shoppingList"'));
      return http.Response(
        jsonEncode({
          'shoppingList': {
            'items': [
              {
                'originalText': 'ఉప్పు 1 packet',
                'name': 'salt',
                'quantity': 1,
                'unitLabel': 'packet',
                'language': 'Telugu',
                'category': 'Pantry staples',
                'confidence': .91,
              },
              {
                'originalText': 'साबुन dozen',
                'name': 'soap',
                'quantity': 12,
                'unitLabel': 'pcs',
                'language': 'Hindi',
                'category': 'Household',
                'confidence': .88,
              },
            ],
            'warnings': [],
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
    final result = await service.parseShoppingListPhoto(image);

    expect(result.items, hasLength(2));
    expect(result.items.first.name, 'salt');
    expect(result.items.first.addText, 'salt 1 packet');
    expect(result.items.last.quantity, 12);
  });
}
