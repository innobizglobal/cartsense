import 'package:flutter_test/flutter_test.dart';
import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/models/shopping_trip.dart';

void main() {
  test('receipt arithmetic includes quantity and discount', () {
    final receipt = Receipt(
      id: '1',
      store: 'Test',
      purchasedAt: DateTime(2026),
      printedTotal: 190,
      items: [
        ReceiptItem(
            name: 'Rice',
            quantity: 2,
            unitPrice: 100,
            discount: 10,
            confidence: .9),
      ],
    );
    expect(receipt.calculatedTotal, 190);
    expect(receipt.reconciled, isTrue);
  });

  test('low confidence item requires review', () {
    final item = ReceiptItem(
        name: 'Milk', quantity: 1, unitPrice: 60, discount: 0, confidence: .7);
    expect(item.needsReview, isTrue);
    expect(item.category, GroceryCategory.dairy);
  });

  test('AI receipt includes separate tax and requires real verification', () {
    final receipt = Receipt(
      id: 'ai-1',
      store: 'D Mart',
      purchasedAt: DateTime(2026, 8, 2),
      printedTotal: 118,
      printedItemCount: 1,
      taxTotal: 18,
      overallConfidence: .94,
      recognitionSource: 'ai_enhanced',
      items: [
        ReceiptItem(
          name: 'Grocery item',
          quantity: 1,
          unitPrice: 100,
          parsedLineTotal: 100,
          discount: 0,
          confidence: .92,
        ),
      ],
    );

    expect(receipt.itemSubtotal, 100);
    expect(receipt.calculatedTotal, 118);
    expect(receipt.confidentlyReconciled, isTrue);
    receipt.printedItemCount = 23;
    expect(receipt.confidentlyReconciled, isFalse);
  });

  test('AI fields survive local JSON storage', () {
    final original = Receipt(
      id: 'ai-2',
      store: 'D Mart Balanagar',
      purchasedAt: DateTime(2026, 8, 2),
      printedTotal: 5638.20,
      printedItemCount: 23,
      printedQuantityTotal: 28,
      taxTotal: 377.14,
      overallConfidence: .86,
      warnings: const ['Folded receipt; review one row.'],
      recognitionSource: 'ai_enhanced',
      items: [
        ReceiptItem(
          name: 'HERITAGE PANEER',
          quantity: 1,
          unitPrice: 90,
          parsedLineTotal: 90,
          discount: 0,
          confidence: .95,
        ),
      ],
    );

    final decoded = Receipt.decode(original.encode());
    expect(decoded.isAiEnhanced, isTrue);
    expect(decoded.printedItemCount, 23);
    expect(decoded.printedQuantityTotal, 28);
    expect(decoded.taxTotal, 377.14);
    expect(decoded.items.single.parsedLineTotal, 90);
    expect(decoded.warnings, hasLength(1));
    expect(decoded.items.single.category, GroceryCategory.dairy);
  });

  test('shopping trip result survives receipt storage', () {
    final receipt = Receipt(
      id: 'trip-bill',
      store: 'D-Mart',
      purchasedAt: DateTime(2026, 8, 3),
      printedTotal: 172,
      items: [],
      shoppingTrip: ShoppingTripResult(
        receiptId: 'trip-bill',
        store: 'D-Mart',
        reconciledAt: DateTime(2026, 8, 3, 18),
        billTotal: 172,
        plannedEstimate: 170,
        matches: const [
          TripMatchSnapshot(
            plannedItemId: 'tea',
            plannedName: 'Tea',
            purchasedName: 'Tetley Classic',
            category: GroceryCategory.teaCoffee,
            plannedQuantity: 1,
            purchasedQuantity: 1,
            expectedTotal: 170,
            actualTotal: 172,
            confidence: .84,
          ),
        ],
        missing: const [],
        unplanned: const [],
      ),
    );

    final decoded = Receipt.decode(receipt.encode());
    expect(decoded.shoppingTrip, isNotNull);
    expect(
        decoded.shoppingTrip!.matches.single.purchasedName, 'Tetley Classic');
    expect(decoded.shoppingTrip!.matchedPriceDifference, 2);
  });
}
