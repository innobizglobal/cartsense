import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../models/shopping_item.dart';

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

class StoreCartOption {
  const StoreCartOption({
    required this.storeName,
    required this.total,
    required this.knownItems,
    required this.missingItems,
  });

  final String storeName;
  final double total;
  final int knownItems;
  final List<String> missingItems;

  factory StoreCartOption.fromJson(Map<String, dynamic> json) =>
      StoreCartOption(
        storeName: json['storeName']?.toString() ?? 'Known store',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        knownItems: (json['knownItems'] as num?)?.toInt() ?? 0,
        missingItems: ((json['missingItems'] as List?) ?? [])
            .map((item) => item.toString())
            .toList(),
      );
}

class CartRemovalSuggestion {
  const CartRemovalSuggestion({
    required this.name,
    required this.savesAbout,
  });

  final String name;
  final double savesAbout;

  factory CartRemovalSuggestion.fromJson(Map<String, dynamic> json) =>
      CartRemovalSuggestion(
        name: json['name']?.toString() ?? '',
        savesAbout: (json['savesAbout'] as num?)?.toDouble() ?? 0,
      );
}

class OnlineCartComparison {
  const OnlineCartComparison({
    required this.plannedTotal,
    required this.bestKnownTotal,
    required this.budget,
    required this.overBudgetBy,
    required this.storeOptions,
    required this.removalSuggestions,
  });

  final double plannedTotal;
  final double bestKnownTotal;
  final double budget;
  final double overBudgetBy;
  final List<StoreCartOption> storeOptions;
  final List<CartRemovalSuggestion> removalSuggestions;

  factory OnlineCartComparison.fromJson(Map<String, dynamic> json) =>
      OnlineCartComparison(
        plannedTotal: (json['plannedTotal'] as num?)?.toDouble() ?? 0,
        bestKnownTotal: (json['bestKnownTotal'] as num?)?.toDouble() ?? 0,
        budget: (json['budget'] as num?)?.toDouble() ?? 0,
        overBudgetBy: (json['overBudgetBy'] as num?)?.toDouble() ?? 0,
        storeOptions: ((json['storeOptions'] as List?) ?? [])
            .whereType<Map>()
            .map((item) => StoreCartOption.fromJson(
                  item.cast<String, dynamic>(),
                ))
            .toList(),
        removalSuggestions: ((json['removalSuggestions'] as List?) ?? [])
            .whereType<Map>()
            .map((item) => CartRemovalSuggestion.fromJson(
                  item.cast<String, dynamic>(),
                ))
            .toList(),
      );
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
    String providers = 'receipt,shelf,demo',
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

  Future<void> uploadReceipt(Receipt receipt) async {
    final items = receipt.items
        .where((item) => item.unitPrice > 0 || item.total > 0)
        .map((item) => {
              'productName': item.name,
              'quantity': item.quantity,
              'unitPrice': item.unitPrice,
              'sellingPrice': item.unitPrice > 0 ? item.unitPrice : item.total,
              'category': item.category,
              'confidence': item.confidence,
            })
        .toList();
    if (items.isEmpty) return;
    await _postJson('/api/price/ingest/receipt', {
      'receiptId': receipt.id,
      'storeName': receipt.store,
      'purchasedAt': receipt.purchasedAt.toIso8601String(),
      'items': items,
    });
  }

  Future<void> uploadShelfPrice(ShoppingItem item) async {
    final price = item.salePrice ?? item.expectedUnitPrice;
    if (price <= 0) return;
    await _postJson('/api/price/ingest/shelf', {
      'storeName': item.latestStore.isNotEmpty ? item.latestStore : 'Shelf',
      'items': [
        {
          'productName': item.name,
          'quantity': item.quantity,
          'sellingPrice': price,
          'mrp': item.mrp,
          'category': item.category,
          'confidence': .9,
        }
      ],
    });
  }

  Future<OnlineCartComparison> compareCart(
    List<ShoppingItem> items, {
    double budget = 0,
  }) async {
    final decoded = await _postJson('/api/price/cart/compare', {
      'budget': budget,
      'providers': 'receipt,shelf,demo',
      'items': items
          .map((item) => {
                'name': item.name,
                'quantity': item.quantity,
                'expectedUnitPrice': item.expectedUnitPrice,
                'category': item.category,
              })
          .toList(),
    });
    return OnlineCartComparison.fromJson(decoded);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await client
        .post(
          uri,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Price API returned ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
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
