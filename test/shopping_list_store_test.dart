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

  test('preserves edits, notes, reminders and receipt origin', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ShoppingListStore();
    final reminder = DateTime(2026, 8, 10, 9);
    final item = ShoppingItem(
      id: 'tea-1',
      name: 'Tetley Classic',
      quantity: 2,
      category: 'Tea & coffee',
      expectedUnitPrice: 172,
      bestUnitPrice: 160,
      bestStore: 'Value Mart',
      latestStore: 'D-Mart',
      note: '250g pack',
      remindAt: reminder,
      sourceReceiptId: 'bill-1',
      createdAt: DateTime(2026, 8, 2),
    );

    await store.add(item);
    final saved = (await store.load()).single;

    expect(saved.category, 'Tea & coffee');
    expect(saved.latestStore, 'D-Mart');
    expect(saved.note, '250g pack');
    expect(saved.remindAt, reminder);
    expect(saved.sourceReceiptId, 'bill-1');
    expect(saved.isReminderDue(DateTime(2026, 8, 11)), isTrue);
  });

  test('combines equivalent product names with different pack formatting',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = ShoppingListStore();
    ShoppingItem product(String name) => ShoppingItem(
          id: name,
          name: name,
          quantity: 1,
          category: 'Tea & coffee',
          expectedUnitPrice: 100,
          bestUnitPrice: 90,
          bestStore: 'D-Mart',
          createdAt: DateTime(2026, 8, 2),
        );

    await store.add(product('Tetley Classic 250g'));
    await store.add(product('Tetley Classic 250 GM'));

    final saved = await store.load();
    expect(saved, hasLength(1));
    expect(saved.single.quantity, 2);
  });
}
