import 'package:cartsense_lite/models/product_catalog.dart';
import 'package:cartsense_lite/models/receipt.dart';
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
  test('generic tea search finds tea products from receipt history', () {
    final catalog = ProductCatalog.fromReceipts([
      _bill(
        id: 'new',
        store: 'D-Mart',
        date: DateTime(2026, 8, 2),
        items: [_item('Tetley Classic 250g', GroceryCategory.teaCoffee, 172)],
      ),
      _bill(
        id: 'old',
        store: 'Value Mart',
        date: DateTime(2026, 7, 2),
        items: [_item('Tetley Classic 250 GM', GroceryCategory.teaCoffee, 160)],
      ),
    ]);

    final matches = catalog.search('Tea');

    expect(matches, isNotEmpty);
    expect(matches.first.name, 'Tetley Classic 250g');
    expect(matches.first.category, GroceryCategory.teaCoffee);
    expect(matches.first.latestUnitPrice, 172);
    expect(matches.first.bestUnitPrice, 160);
    expect(matches.first.bestStore, 'Value Mart');
  });

  test('category recognition finds oils even without an exact name', () {
    final catalog = ProductCatalog.fromReceipts([
      _bill(
        id: 'oil',
        store: 'Fresh Mart',
        date: DateTime(2026, 8, 2),
        items: [
          _item('Gold Drop Refined Oil 1L', GroceryCategory.cookingOils, 148),
        ],
      ),
    ]);

    expect(catalog.categoryFor('sunflower oil'), GroceryCategory.cookingOils);
    expect(catalog.search('oil').single.name, contains('Gold Drop'));
  });

  test('shopping search does not return unrelated popular products', () {
    final catalog = ProductCatalog.fromReceipts([
      _bill(
        id: 'mixed',
        store: 'D-Mart',
        date: DateTime(2026, 8, 2),
        items: [
          _item('Milk 500ml', GroceryCategory.dairy, 32),
          _item('T Shirt', GroceryCategory.other, 399),
          _item('Veda Karam Powder', GroceryCategory.pantry, 80),
          _item('Aashirvaad Atta', GroceryCategory.pantry, 220),
        ],
      ),
    ]);

    final matches = catalog.search('milk');

    expect(matches.map((item) => item.name), contains('Milk 500ml'));
    expect(matches.map((item) => item.name), isNot(contains('T Shirt')));
    expect(
        matches.map((item) => item.name), isNot(contains('Veda Karam Powder')));
    expect(
        matches.map((item) => item.name), isNot(contains('Aashirvaad Atta')));
  });
}
