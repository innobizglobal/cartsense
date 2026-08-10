import 'dart:convert';

import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/models/shopping_item.dart';
import 'package:cartsense_lite/services/price_intelligence_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('decodes Hostinger price search offers', () async {
    final api = PriceIntelligenceApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/price/search');
        expect(request.url.queryParameters['q'], 'tea');
        expect(request.url.queryParameters['providers'], 'demo');
        return http.Response(
          jsonEncode({
            'query': 'tea',
            'offers': [
              {
                'provider': 'demo',
                'providerLabel': 'CartSense demo prices',
                'productName': 'Tetley Classic Tea 250g',
                'brand': 'Tetley',
                'packSize': '250g',
                'mrp': 180,
                'sellingPrice': 165,
                'currency': 'INR',
                'confidence': 0.98,
                'source': 'demo',
                'lastCheckedAt': '2026-08-10T06:05:17.045Z',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final offers = await api.search('tea', providers: 'demo');

    expect(offers, hasLength(1));
    expect(offers.single.productName, 'Tetley Classic Tea 250g');
    expect(offers.single.sellingPrice, 165);
    expect(offers.single.source, 'demo');
  });

  test('uploads receipt prices to central price memory', () async {
    late Map<String, dynamic> posted;
    final api = PriceIntelligenceApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/price/ingest/receipt');
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'status': 'ok', 'inserted': 1}), 200);
      }),
    );

    await api.uploadReceipt(Receipt(
      id: 'bill-1',
      store: 'DMart Balanagar',
      purchasedAt: DateTime(2026, 8, 10),
      printedTotal: 165,
      items: [
        ReceiptItem(
          name: 'Tetley Classic Tea 250g',
          quantity: 1,
          unitPrice: 165,
          discount: 0,
          confidence: .92,
          category: GroceryCategory.teaCoffee,
        ),
      ],
    ));

    expect(posted['storeName'], 'DMart Balanagar');
    expect(posted['items'], hasLength(1));
    expect((posted['items'] as List).single['productName'],
        'Tetley Classic Tea 250g');
  });

  test('decodes store-wise cart comparison', () async {
    final api = PriceIntelligenceApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/price/cart/compare');
        return http.Response(
          jsonEncode({
            'plannedTotal': 170,
            'bestKnownTotal': 160,
            'budget': 150,
            'overBudgetBy': 10,
            'storeOptions': [
              {
                'storeName': 'DMart Balanagar',
                'total': 160,
                'knownItems': 1,
                'missingItems': [],
              }
            ],
            'removalSuggestions': [
              {'name': 'Tetley Classic Tea 250g', 'savesAbout': 170}
            ],
          }),
          200,
        );
      }),
    );

    final comparison = await api.compareCart([
      ShoppingItem(
        id: 'tea',
        name: 'Tetley Classic Tea 250g',
        quantity: 1,
        category: GroceryCategory.teaCoffee,
        expectedUnitPrice: 170,
        bestUnitPrice: 160,
        bestStore: 'DMart Balanagar',
        createdAt: DateTime(2026, 8, 10),
      ),
    ], budget: 150);

    expect(comparison.bestKnownTotal, 160);
    expect(comparison.storeOptions.single.storeName, 'DMart Balanagar');
    expect(comparison.removalSuggestions.single.savesAbout, 170);
  });
}
