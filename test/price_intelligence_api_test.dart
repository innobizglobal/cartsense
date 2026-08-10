import 'dart:convert';

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

    final offers = await api.search('tea');

    expect(offers, hasLength(1));
    expect(offers.single.productName, 'Tetley Classic Tea 250g');
    expect(offers.single.sellingPrice, 165);
    expect(offers.single.source, 'demo');
  });
}
