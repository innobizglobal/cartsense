import 'package:shared_preferences/shared_preferences.dart';
import '../models/shopping_item.dart';

class ShoppingListStore {
  static const _key = 'cartsense_shopping_list_v1';

  Future<List<ShoppingItem>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? [])
        .map(ShoppingItem.decode)
        .toList();
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
    final existing = items.indexWhere(
      (value) =>
          value.name.trim().toLowerCase() == item.name.trim().toLowerCase(),
    );
    if (existing >= 0) {
      items[existing].quantity += item.quantity;
      items[existing].checked = false;
    } else {
      items.add(item);
    }
    await saveAll(items);
  }
}
