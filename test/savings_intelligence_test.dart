import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/models/savings_intelligence.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _receipt({
  required String id,
  required String store,
  required DateTime date,
  required String product,
  required double price,
}) =>
    Receipt(
      id: id,
      store: store,
      purchasedAt: date,
      printedTotal: price,
      items: [
        ReceiptItem(
          name: product,
          quantity: 1,
          unitPrice: price,
          discount: 0,
          confidence: 1,
        ),
      ],
    );

void main() {
  test('finds price rises, cheaper stores and repeat-purchase suggestions', () {
    final receipts = [
      _receipt(
        id: 'latest',
        store: 'Store B',
        date: DateTime(2026, 8, 1),
        product: 'Heritage Milk 1L',
        price: 60,
      ),
      _receipt(
        id: 'older',
        store: 'Store A',
        date: DateTime(2026, 7, 1),
        product: 'HERITAGE MILK 1000 ml',
        price: 50,
      ),
    ];

    final result = SavingsIntelligence.fromReceipts(
      receipts,
      now: DateTime(2026, 8, 2),
    );

    expect(result.currentMonthTotal, 60);
    expect(result.priceRises, hasLength(1));
    expect(result.priceRises.single.priceChangePercent, 20);
    expect(result.cheaperStoreOptions.single.bestStore, 'Store A');
    expect(result.frequentProducts.single.purchaseCount, 2);
  });

  test('finds price drops for repeated products', () {
    final receipts = [
      _receipt(
        id: 'latest',
        store: 'Store B',
        date: DateTime(2026, 8, 1),
        product: 'Gold Drop Oil 1L',
        price: 140,
      ),
      _receipt(
        id: 'older',
        store: 'Store A',
        date: DateTime(2026, 7, 1),
        product: 'GOLD DROP OIL 1 L',
        price: 160,
      ),
    ];

    final result = SavingsIntelligence.fromReceipts(
      receipts,
      now: DateTime(2026, 8, 2),
    );

    expect(result.priceDrops, hasLength(1));
    expect(result.priceDrops.single.priceChangePercent, -12.5);
  });

  test('normalizes pack sizes and punctuation for product comparisons', () {
    expect(
      normalizedProductName('Dabur Glucose-200g'),
      normalizedProductName('DABUR GLUCOSE 200 GM'),
    );
  });
}
