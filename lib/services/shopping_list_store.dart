import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../models/shopping_item.dart';

class ShoppingListStore {
  static const _key = 'cartsense_shopping_list_v1';

  Future<List<ShoppingItem>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final items = (preferences.getStringList(_key) ?? [])
        .map(ShoppingItem.decode)
        .toList();
    var changed = false;
    for (final item in items) {
      if (item.category == GroceryCategory.other) {
        final inferred = GroceryCategory.infer(item.name);
        if (inferred != GroceryCategory.other) {
          item.category = inferred;
          changed = true;
        }
      }
    }
    if (changed) await saveAll(items);
    return items;
  }

  Future<void> saveAll(List<ShoppingItem> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key,
      items.map((item) => item.encode()).toList(),
    );
  }

  Future<void> add(ShoppingItem item) async {
    final items = await load();
    final key = normalizedProductName(item.name);
    final existing = items.indexWhere(
      (value) => normalizedProductName(value.name) == key,
    );
    if (existing >= 0) {
      final current = items[existing];
      current.quantity += item.quantity;
      current.checked = false;
      current.completedAt = null;
      if (item.category != GroceryCategory.other) {
        current.category = item.category;
      }
      if (item.expectedUnitPrice > 0) {
        current.expectedUnitPrice = item.expectedUnitPrice;
      }
      if (item.bestUnitPrice > 0) current.bestUnitPrice = item.bestUnitPrice;
      if (item.bestStore.isNotEmpty) current.bestStore = item.bestStore;
      if (item.latestStore.isNotEmpty) current.latestStore = item.latestStore;
      if (item.note.isNotEmpty) current.note = item.note;
      current.remindAt ??= item.remindAt;
    } else {
      items.add(item);
    }
    await saveAll(items);
  }

  Future<void> update(ShoppingItem item) async {
    final items = await load();
    final index = items.indexWhere((value) => value.id == item.id);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await saveAll(items);
  }
}
