import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/receipt.dart';
import '../models/savings_intelligence.dart';

class OnlinePriceOffer {
  const OnlinePriceOffer({
    required this.provider,
    required this.providerLabel,
    required this.productName,
    required this.sellingPrice,
    required this.currency,
    required this.source,
    required this.lastCheckedAt,
    this.brand,
    this.packSize,
    this.mrp,
    this.unitPrice,
    this.unit,
    this.confidence = 0,
  });

  final String provider;
  final String providerLabel;
  final String productName;
  final String? brand;
  final String? packSize;
  final double? mrp;
  final double sellingPrice;
  final String currency;
  final double? unitPrice;
  final String? unit;
  final double confidence;
  final String source;
  final DateTime lastCheckedAt;

  factory OnlinePriceOffer.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return OnlinePriceOffer(
      provider: (json['provider'] as String?) ?? 'unknown',
      providerLabel: (json['providerLabel'] as String?) ?? 'Online store',
      productName: (json['productName'] as String?) ?? 'Unknown product',
      brand: json['brand'] as String?,
      packSize: json['packSize'] as String?,
      mrp: number(json['mrp']),
      sellingPrice: number(json['sellingPrice']) ?? 0,
      currency: (json['currency'] as String?) ?? 'INR',
      unitPrice: number(json['unitPrice']),
      unit: json['unit'] as String?,
      confidence: number(json['confidence']) ?? 0,
      source: (json['source'] as String?) ?? 'live',
      lastCheckedAt: DateTime.tryParse(
            (json['lastCheckedAt'] as String?) ?? '',
          ) ??
          DateTime.now(),
    );
  }
}

class OnlinePriceComparison {
  const OnlinePriceComparison({
    required this.localProductName,
    required this.localPrice,
    required this.localStore,
    required this.offer,
  });

  final String localProductName;
  final double localPrice;
  final String localStore;
  final OnlinePriceOffer offer;

  // Compare pack/sale price first. Unit-price comparison will be added once the
  // mobile app also captures pack sizes consistently from receipts.
  double get comparableOnlinePrice => offer.sellingPrice;

  double get possibleSaving =>
      (localPrice - comparableOnlinePrice).clamp(0, double.infinity);

  bool get isCheaperOnline => possibleSaving >= 1;
}

class PriceIntelligenceApi {
  PriceIntelligenceApi({
    http.Client? client,
    this.baseUrl = 'https://cartsenseapi.londongastrocare.in',
  }) : client = client ?? http.Client();

  final http.Client client;
  final String baseUrl;

  Future<List<OnlinePriceOffer>> search(
    String query, {
    String providers = 'demo',
    int limit = 4,
  }) async {
    final uri = Uri.parse('$baseUrl/api/price/search').replace(
      queryParameters: {
        'q': query,
        'providers': providers,
        'limit': '$limit',
      },
    );
    final response = await client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Price API returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final offers = (decoded['offers'] as List? ?? [])
        .whereType<Map>()
        .map((value) => OnlinePriceOffer.fromJson(
              value.cast<String, dynamic>(),
            ))
        .where((offer) => offer.sellingPrice > 0)
        .toList();
    offers.sort(
      (a, b) => (a.unitPrice ?? a.sellingPrice)
          .compareTo(b.unitPrice ?? b.sellingPrice),
    );
    return offers;
  }

  Future<List<OnlinePriceComparison>> compareReceiptPrices(
    List<Receipt> receipts, {
    int productLimit = 4,
  }) async {
    final candidates = _recentProducts(receipts).take(productLimit).toList();
    final comparisons = <OnlinePriceComparison>[];
    for (final candidate in candidates) {
      try {
        final offers = await search(candidate.name, limit: 3);
        if (offers.isEmpty) continue;
        comparisons.add(OnlinePriceComparison(
          localProductName: candidate.name,
          localPrice: candidate.unitPrice,
          localStore: candidate.store,
          offer: offers.first,
        ));
      } on Object {
        // Keep Insights useful even when a provider blocks or the phone is
        // offline. The screen will fall back to receipt-only intelligence.
      }
    }
    comparisons.sort((a, b) {
      final saving = b.possibleSaving.compareTo(a.possibleSaving);
      if (saving != 0) return saving;
      return a.comparableOnlinePrice.compareTo(b.comparableOnlinePrice);
    });
    return comparisons;
  }

  List<_LocalPriceCandidate> _recentProducts(List<Receipt> receipts) {
    final candidates = <String, _LocalPriceCandidate>{};
    final sorted = [...receipts]
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    for (final receipt in sorted) {
      for (final item in receipt.items) {
        if (item.quantity <= 0) continue;
        final key = normalizedProductName(item.name);
        if (key.length < 2 || candidates.containsKey(key)) continue;
        final unitPrice =
            item.unitPrice > 0 ? item.unitPrice : item.total / item.quantity;
        if (!unitPrice.isFinite || unitPrice <= 0) continue;
        candidates[key] = _LocalPriceCandidate(
          name: item.name,
          unitPrice: unitPrice,
          store: receipt.store.trim().isEmpty ? 'saved receipt' : receipt.store,
          purchasedAt: receipt.purchasedAt,
        );
      }
    }
    final values = candidates.values.toList()
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    return values;
  }
}

class _LocalPriceCandidate {
  const _LocalPriceCandidate({
    required this.name,
    required this.unitPrice,
    required this.store,
    required this.purchasedAt,
  });

  final String name;
  final double unitPrice;
  final String store;
  final DateTime purchasedAt;
}
