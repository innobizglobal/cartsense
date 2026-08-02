import 'package:cartsense_lite/services/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ReceiptTextParser();

  test('extracts an Indian grocery receipt and reconciles a discount', () {
    final receipt = parser.parse(
      '''
FRESH MART
GSTIN 36ABCDE1234F1Z5
Date: 02/08/2026
Milk 2 30.00 60.00
Rice 1 120.00 120.00
Discount 10.00
Grand Total 170.00
Thank You
''',
      now: DateTime(2026, 8, 3),
      imagePath: '/receipt.jpg',
    );

    expect(receipt.store, 'Fresh Mart');
    expect(receipt.purchasedAt, DateTime(2026, 8, 2));
    expect(receipt.imagePath, '/receipt.jpg');
    expect(receipt.items, hasLength(2));
    expect(receipt.items.first.name, 'Milk');
    expect(receipt.items.first.quantity, 2);
    expect(receipt.items.first.unitPrice, 30);
    expect(receipt.items.last.discount, 10);
    expect(receipt.printedTotal, 170);
    expect(receipt.calculatedTotal, 170);
    expect(receipt.reconciled, isTrue);
  });

  test('supports weighted items and numbers embedded in product names', () {
    final receipt = parser.parse(
      '''
GREEN BASKET
03-08-2026
Bananas 1.250 40.00 50.00
Milk 500ml 35.00
TOTAL 85.00
''',
      now: DateTime(2026, 8, 3),
    );

    expect(receipt.items, hasLength(2));
    expect(receipt.items.first.quantity, 1.25);
    expect(receipt.items.first.unitPrice, 40);
    expect(receipt.items.last.name, 'Milk 500ml');
    expect(receipt.items.last.unitPrice, 35);
    expect(receipt.reconciled, isTrue);
  });

  test('uses safe fallbacks when store, date and total are absent', () {
    final now = DateTime(2026, 8, 3, 10, 30);
    final receipt = parser.parse('42.00\nBread 42.00', now: now);

    expect(receipt.store, 'Scanned grocery bill');
    expect(receipt.purchasedAt, now);
    expect(receipt.printedTotal, 42);
    expect(receipt.items.single.name, 'Bread');
  });
}
