import 'receipt.dart';

String normalizedProductName(String value) => value
    .toLowerCase()
    .replaceAll(
        RegExp(r'\b\d+(?:\.\d+)?\s*(?:kg|g|gm|ml|l|ltr|pcs?|nos?)\b'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

class MonthlySpend {
  const MonthlySpend(this.month, this.total);

  final DateTime month;
  final double total;
}

class ProductPriceInsight {
  const ProductPriceInsight({
    required this.name,
    required this.latestPrice,
    required this.previousPrice,
    required this.bestPrice,
    required this.latestStore,
    required this.bestStore,
    required this.purchaseCount,
  });

  final String name;
  final double latestPrice;
  final double? previousPrice;
  final double bestPrice;
  final String latestStore;
  final String bestStore;
  final int purchaseCount;

  double get priceChangePercent => previousPrice == null || previousPrice == 0
      ? 0
      : ((latestPrice - previousPrice!) / previousPrice!) * 100;

  double get possibleSaving =>
      (latestPrice - bestPrice).clamp(0, double.infinity);
}

class FrequentProduct {
  const FrequentProduct({
    required this.name,
    required this.category,
    required this.purchaseCount,
    required this.latestPrice,
    required this.bestPrice,
    required this.bestStore,
    required this.lastPurchased,
    required this.averageDaysBetweenPurchases,
  });

  final String name;
  final String category;
  final int purchaseCount;
  final double latestPrice;
  final double bestPrice;
  final String bestStore;
  final DateTime lastPurchased;
  final int? averageDaysBetweenPurchases;

  bool isDueAt(DateTime now) =>
      averageDaysBetweenPurchases != null &&
      now.difference(lastPurchased).inDays >=
          (averageDaysBetweenPurchases! * .8).round();
}

class SavingsIntelligence {
  const SavingsIntelligence({
    required this.monthlySpend,
    required this.categoryTotals,
    required this.priceInsights,
    required this.frequentProducts,
  });

  final List<MonthlySpend> monthlySpend;
  final Map<String, double> categoryTotals;
  final List<ProductPriceInsight> priceInsights;
  final List<FrequentProduct> frequentProducts;

  double get currentMonthTotal =>
      monthlySpend.isEmpty ? 0 : monthlySpend.last.total;

  double get possibleBasketSaving => priceInsights.fold(
        0,
        (total, item) => total + item.possibleSaving,
      );

  List<ProductPriceInsight> get priceRises => priceInsights
      .where((item) => item.purchaseCount > 1 && item.priceChangePercent >= 5)
      .toList()
    ..sort((a, b) => b.priceChangePercent.compareTo(a.priceChangePercent));

  List<ProductPriceInsight> get cheaperStoreOptions => priceInsights
      .where((item) =>
          item.bestStore != item.latestStore && item.possibleSaving >= 1)
      .toList()
    ..sort((a, b) => b.possibleSaving.compareTo(a.possibleSaving));

  factory SavingsIntelligence.fromReceipts(
    List<Receipt> receipts, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final months = List.generate(6, (index) {
      final offset = 5 - index;
      return DateTime(today.year, today.month - offset);
    });
    final monthlySpend = months
        .map((month) => MonthlySpend(
              month,
              receipts
                  .where((receipt) =>
                      receipt.purchasedAt.year == month.year &&
                      receipt.purchasedAt.month == month.month)
                  .fold(
                      0.0, (total, receipt) => total + receipt.calculatedTotal),
            ))
        .toList();

    final categoryTotals = <String, double>{};
    for (final receipt in receipts.where((receipt) =>
        receipt.purchasedAt.year == today.year &&
        receipt.purchasedAt.month == today.month)) {
      for (final item in receipt.items) {
        categoryTotals.update(
          item.category,
          (value) => value + item.total,
          ifAbsent: () => item.total,
        );
      }
    }

    final observations = <String, List<_PriceObservation>>{};
    for (final receipt in receipts) {
      for (final item in receipt.items) {
        final key = normalizedProductName(item.name);
        if (key.length < 2 || item.quantity <= 0) continue;
        final price =
            item.unitPrice > 0 ? item.unitPrice : item.total / item.quantity;
        if (!price.isFinite || price <= 0) continue;
        observations.putIfAbsent(key, () => []).add(_PriceObservation(
              name: item.name,
              category: item.category,
              price: price,
              store: receipt.store,
              purchasedAt: receipt.purchasedAt,
            ));
      }
    }

    final prices = <ProductPriceInsight>[];
    final frequent = <FrequentProduct>[];
    for (final values in observations.values) {
      values.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
      final latest = values.first;
      final previous = values.length > 1 ? values[1] : null;
      final best = values.reduce((a, b) => a.price <= b.price ? a : b);
      prices.add(ProductPriceInsight(
        name: latest.name,
        latestPrice: latest.price,
        previousPrice: previous?.price,
        bestPrice: best.price,
        latestStore: latest.store,
        bestStore: best.store,
        purchaseCount: values.length,
      ));

      final uniqueDays = values
          .map((value) => DateTime(
                value.purchasedAt.year,
                value.purchasedAt.month,
                value.purchasedAt.day,
              ))
          .toSet()
          .toList()
        ..sort();
      int? interval;
      if (uniqueDays.length > 1) {
        var totalDays = 0;
        for (var index = 1; index < uniqueDays.length; index++) {
          totalDays +=
              uniqueDays[index].difference(uniqueDays[index - 1]).inDays;
        }
        interval = (totalDays / (uniqueDays.length - 1)).round().clamp(1, 365);
      }
      if (values.length >= 2) {
        frequent.add(FrequentProduct(
          name: latest.name,
          category: latest.category,
          purchaseCount: values.length,
          latestPrice: latest.price,
          bestPrice: best.price,
          bestStore: best.store,
          lastPurchased: latest.purchasedAt,
          averageDaysBetweenPurchases: interval,
        ));
      }
    }

    prices.sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));
    frequent.sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));
    return SavingsIntelligence(
      monthlySpend: monthlySpend,
      categoryTotals: categoryTotals,
      priceInsights: prices,
      frequentProducts: frequent,
    );
  }
}

class _PriceObservation {
  const _PriceObservation({
    required this.name,
    required this.category,
    required this.price,
    required this.store,
    required this.purchasedAt,
  });

  final String name;
  final String category;
  final double price;
  final String store;
  final DateTime purchasedAt;
}
