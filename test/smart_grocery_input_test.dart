import 'package:cartsense_lite/models/product_catalog.dart';
import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/services/smart_grocery_input.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _bill({
  required String id,
  required String store,
  required DateTime date,
  required List<ReceiptItem> items,
}) =>
    Receipt(
      id: id,
      store: store,
      purchasedAt: date,
      items: items,
      printedTotal: items.fold(0, (sum, item) => sum + item.total),
    );

ReceiptItem _item(String name, String category, double price) => ReceiptItem(
      name: name,
      category: category,
      quantity: 1,
      unitPrice: price,
      discount: 0,
      confidence: 1,
    );

void main() {
  test('understands packets, dozen and past product aliases', () {
    final catalog = ProductCatalog.fromReceipts([
      _bill(
        id: 'past',
        store: 'D-Mart',
        date: DateTime(2026, 8, 1),
        items: [
          _item('Tata Salt 1kg', GroceryCategory.pantry, 28),
          _item('Dove Soap 100g', GroceryCategory.personalCare, 62),
          _item('Colgate Strong Teeth Toothpaste', GroceryCategory.personalCare,
              110),
        ],
      ),
    ]);
    final parser = SmartGroceryInputParser(catalog);

    final entries = parser.parse('salt 1 packet, soaps dozen, paste');

    expect(entries, hasLength(3));
    expect(entries[0].name, 'Tata Salt 1kg');
    expect(entries[0].quantity, 1);
    expect(entries[0].unitLabel, 'packets');
    expect(entries[1].name, 'Dove Soap 100g');
    expect(entries[1].quantity, 12);
    expect(entries[1].unitLabel, 'pcs');
    expect(entries[2].name, 'Colgate Strong Teeth Toothpaste');
    expect(entries[2].quantity, 1);
    expect(entries[2].matchedProduct?.latestUnitPrice, 110);
  });

  test('normalizes spoken English Hindi and Telugu grocery words', () {
    final parser = SmartGroceryInputParser(ProductCatalog.fromReceipts([]));

    final entries = parser.parse('नमक एक पैकेट और సబ్బు డజన్');

    expect(entries, hasLength(2));
    expect(entries[0].name, 'Salt');
    expect(entries[0].quantity, 1);
    expect(entries[0].unitLabel, 'packets');
    expect(entries[1].name, 'Soap');
    expect(entries[1].quantity, 12);
  });
}
