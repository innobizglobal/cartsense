import 'receipt.dart';
import 'savings_intelligence.dart';

class CatalogProduct {
  const CatalogProduct({
    required this.name,
    required this.category,
    required this.latestUnitPrice,
    required this.bestUnitPrice,
    required this.latestStore,
    required this.bestStore,
    required this.purchaseCount,
    required this.lastPurchased,
  });

  final String name;
  final String category;
  final double latestUnitPrice;
  final double bestUnitPrice;
  final String latestStore;
  final String bestStore;
  final int purchaseCount;
  final DateTime lastPurchased;

  String get key => normalizedProductName(name);
}

class ProductCatalog {
  const ProductCatalog(this.products);

  final List<CatalogProduct> products;

  factory ProductCatalog.fromReceipts(List<Receipt> receipts) {
    final observations = <String, List<_CatalogObservation>>{};
    for (final receipt in receipts) {
      for (final item in receipt.items) {
        final key = normalizedProductName(item.name);
        if (key.length < 2 || item.quantity <= 0) continue;
        final unitPrice =
            item.unitPrice > 0 ? item.unitPrice : item.total / item.quantity;
        if (!unitPrice.isFinite || unitPrice <= 0) continue;
        observations.putIfAbsent(key, () => []).add(_CatalogObservation(
              name: item.name,
              category: item.category,
              unitPrice: unitPrice,
              store: receipt.store,
              purchasedAt: receipt.purchasedAt,
            ));
      }
    }

    final products = observations.values.map((values) {
      values.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
      final latest = values.first;
      final best = values.reduce(
        (left, right) => left.unitPrice <= right.unitPrice ? left : right,
      );
      return CatalogProduct(
        name: latest.name,
        category: latest.category,
        latestUnitPrice: latest.unitPrice,
        bestUnitPrice: best.unitPrice,
        latestStore: latest.store,
        bestStore: best.store,
        purchaseCount: values.length,
        lastPurchased: latest.purchasedAt,
      );
    }).toList()
      ..sort((a, b) => b.lastPurchased.compareTo(a.lastPurchased));
    return ProductCatalog(products);
  }

  CatalogProduct? exactMatch(String query) {
    final key = normalizedProductName(query);
    if (key.isEmpty) return null;
    for (final product in products) {
      if (product.key == key) return product;
    }
    return null;
  }

  List<CatalogProduct> search(String query, {int limit = 6}) {
    final key = normalizedProductName(query);
    if (key.isEmpty) {
      return products.take(limit).toList();
    }
    final category = GroceryCategory.infer(query);
    final queryTokens = _intentTokens(key);
    final ranked = <({CatalogProduct product, double score})>[];
    for (final product in products) {
      final productKey = product.key;
      final productTokens = _intentTokens(productKey);
      var score = 0.0;
      var matched = false;
      if (productKey == key) score += 120;
      if (productKey == key) matched = true;
      if (productKey.startsWith(key)) {
        score += 70;
        matched = true;
      }
      if (productKey.contains(key)) {
        score += 55;
        matched = true;
      }
      if (key.length >= 4 && key.contains(productKey)) {
        score += 45;
        matched = true;
      }
      final tokenMatches = queryTokens.intersection(productTokens).length;
      if (tokenMatches > 0) {
        score += tokenMatches * 32;
        matched = true;
      }
      if (category != GroceryCategory.other && product.category == category) {
        score += 48;
      }
      if (!matched) continue;
      score += product.purchaseCount.clamp(0, 10) * .8;
      if (score >= 24) ranked.add((product: product, score: score));
    }
    ranked.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return b.product.lastPurchased.compareTo(a.product.lastPurchased);
    });
    return ranked.take(limit).map((item) => item.product).toList();
  }

  String categoryFor(String name) {
    final exact = exactMatch(name);
    return exact?.category ?? GroceryCategory.infer(name);
  }

  Set<String> _intentTokens(String value) {
    final tokens = value
        .split(' ')
        .where((token) => token.length > 1)
        .map(_canonicalToken)
        .toSet();
    final expanded = <String>{...tokens};
    for (final token in tokens) {
      expanded.addAll(_groceryConcepts[token] ?? const {});
    }
    return expanded;
  }

  String _canonicalToken(String token) => switch (token) {
        'coffe' => 'coffee',
        'chai' => 'tea',
        'tetely' || 'tetly' => 'tetley',
        'wisper' || 'nisper' => 'whisper',
        'panee' => 'paneer',
        'sunfl' => 'sunflower',
        'surfexcel' => 'surf',
        'colgate' => 'toothpaste',
        'paste' => 'toothpaste',
        'soaps' => 'soap',
        'packets' || 'packet' || 'packs' => 'pack',
        _ => token,
      };
}

const _groceryConcepts = <String, Set<String>>{
  'tea': {'tea', 'chai', 'tetley', 'tata', 'red', 'label', 'taj', 'wagh'},
  'chai': {'tea'},
  'tetley': {'tea'},
  'tetly': {'tea'},
  'tetely': {'tea'},
  'coffee': {'coffee', 'bru', 'nescafe', 'continental', 'sunrise'},
  'bru': {'coffee'},
  'nescafe': {'coffee'},
  'toothpaste': {'toothpaste', 'paste', 'tooth', 'colgate', 'pepsodent'},
  'colgate': {'toothpaste'},
  'detergent': {'detergent', 'surf', 'rin', 'ariel', 'washing', 'powder'},
  'surf': {'detergent', 'washing', 'powder'},
  'rin': {'detergent', 'washing', 'powder'},
  'ariel': {'detergent', 'washing', 'powder'},
  'soap': {'soap', 'dove', 'lux', 'santoor', 'cinthol', 'pears'},
  'oil': {'oil', 'sunflower', 'gold', 'drop', 'fortune', 'freedom', 'sundrop'},
  'sunflower': {'oil'},
  'salt': {'salt'},
  'milk': {'milk', 'heritage', 'amul', 'nandini'},
  'paneer': {'paneer', 'panee', 'heritage', 'amul'},
  'grape': {'grape', 'grapes', 'fruit'},
  'grapes': {'grape', 'fruit'},
  'dal': {'dal', 'dhal', 'toor', 'moong', 'urad', 'chana', 'pulse'},
  'dhal': {'dal'},
  'toor': {'dal'},
  'atta': {'atta', 'flour', 'aashirvaad'},
  'pads': {'pads', 'sanitary', 'whisper', 'stayfree', 'sofy'},
  'whisper': {'pads', 'sanitary'},
};

class _CatalogObservation {
  const _CatalogObservation({
    required this.name,
    required this.category,
    required this.unitPrice,
    required this.store,
    required this.purchasedAt,
  });

  final String name;
  final String category;
  final double unitPrice;
  final String store;
  final DateTime purchasedAt;
}
