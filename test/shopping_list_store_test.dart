import 'package:cartsense_lite/models/shopping_item.dart';
import 'package:cartsense_lite/services/shopping_list_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists a shopping list and combines repeated items', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ShoppingListStore();
    ShoppingItem item(double quantity) => ShoppingItem(
          id: quantity.toString(),
          name: 'Milk',
          quantity: quantity,
          category: 'Dairy & chilled',
          expectedUnitPrice: 50,
          bestUnitPrice: 48,
          bestStore: 'Fresh Mart',
          createdAt: DateTime(2026, 8, 2),
        );

    await store.add(item(1));
    await store.add(item(2));

    final saved = await store.load();
    expect(saved, hasLength(1));
    expect(saved.single.quantity, 3);
    expect(saved.single.possibleSaving, 6);
  });
}
