import 'package:flutter_test/flutter_test.dart';
import 'package:cartsense_lite/models/receipt.dart';

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
  });
}
