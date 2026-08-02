import 'receipt.dart';

class SpendingInsights {
  const SpendingInsights({
    required this.total,
    required this.billCount,
    required this.categoryTotals,
  });

  final double total;
  final int billCount;
  final Map<String, double> categoryTotals;

  String? get topCategory {
    if (categoryTotals.isEmpty) return null;
    return categoryTotals.entries
        .reduce((left, right) => left.value >= right.value ? left : right)
        .key;
  }

  double get topCategoryTotal =>
      topCategory == null ? 0 : categoryTotals[topCategory] ?? 0;

  factory SpendingInsights.forMonth(
    List<Receipt> receipts, {
    DateTime? month,
  }) {
    final selected = month ?? DateTime.now();
    final matching = receipts.where(
      (receipt) =>
          receipt.purchasedAt.year == selected.year &&
          receipt.purchasedAt.month == selected.month,
    );
    final categories = <String, double>{};
    var total = 0.0;
    var billCount = 0;
    for (final receipt in matching) {
      total += receipt.calculatedTotal;
      billCount += 1;
      for (final item in receipt.items) {
        categories.update(
          item.category,
          (value) => value + item.total,
          ifAbsent: () => item.total,
        );
      }
    }
    return SpendingInsights(
      total: total,
      billCount: billCount,
      categoryTotals: categories,
    );
  }
}
