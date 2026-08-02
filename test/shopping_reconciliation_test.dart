import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/models/shopping_item.dart';
import 'package:cartsense_lite/models/shopping_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShoppingItem planned({
    required String id,
    required String name,
    required String category,
    required double price,
  }) =>
      ShoppingItem(
        id: id,
        name: name,
        quantity: 1,
        category: category,
        expectedUnitPrice: price,
        bestUnitPrice: price,
        bestStore: 'D-Mart',
        createdAt: DateTime(2026, 8, 2),
      );

  test('matches a generic tea plan to Tetley and separates missing and extras',
      () {
    final plan = [
      planned(
        id: 'tea',
        name: 'Tea',
        category: GroceryCategory.teaCoffee,
        price: 170,
      ),
      planned(
        id: 'milk',
        name: 'Milk',
        category: GroceryCategory.dairy,
        price: 60,
      ),
    ];
    final receipt = Receipt(
      id: 'bill-1',
      store: 'D-Mart',
      purchasedAt: DateTime(2026, 8, 3),
      printedTotal: 222,
      items: [
        ReceiptItem(
          name: 'Tetley Classic 250g',
          quantity: 1,
          unitPrice: 172,
          discount: 0,
          confidence: .95,
        ),
        ReceiptItem(
          name: 'Chocolate bar',
          quantity: 1,
          unitPrice: 50,
          discount: 0,
          confidence: .95,
        ),
      ],
    );

    final assignments = ShoppingReconciliation.suggest(plan, receipt);
    expect(assignments, {'tea': 0});

    final result = ShoppingReconciliation.buildResult(
      planned: plan,
      receipt: receipt,
      assignments: assignments,
      reconciledAt: DateTime(2026, 8, 3, 18),
    );
    expect(result.matches.single.purchasedName, 'Tetley Classic 250g');
    expect(result.missing.single.name, 'Milk');
    expect(result.unplanned.single.name, 'Chocolate bar');
    expect(result.plannedEstimate, 230);
    expect(result.billTotal, 222);
    expect(result.matchedPriceDifference, 2);
  });

  test('never assigns one receipt row to two planned products', () {
    final plan = [
      planned(
        id: 'tea-1',
        name: 'Tea',
        category: GroceryCategory.teaCoffee,
        price: 170,
      ),
      planned(
        id: 'tea-2',
        name: 'Chai',
        category: GroceryCategory.teaCoffee,
        price: 170,
      ),
    ];
    final receipt = Receipt(
      id: 'bill-2',
      store: 'D-Mart',
      purchasedAt: DateTime(2026, 8, 3),
      printedTotal: 172,
      items: [
        ReceiptItem(
          name: 'Tetley Classic',
          quantity: 1,
          unitPrice: 172,
          discount: 0,
          confidence: .95,
        ),
      ],
    );

    final assignments = ShoppingReconciliation.suggest(plan, receipt);
    expect(assignments, hasLength(1));
    expect(assignments.values.toSet(), {0});
  });
}
