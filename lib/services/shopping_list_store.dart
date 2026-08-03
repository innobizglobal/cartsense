import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../models/shopping_item.dart';
import 'product_memory_store.dart';

class ShoppingListStore {
  static const _key = 'cartsense_shopping_list_v1';

  Future<List<ShoppingItem>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final items = (preferences.getStringList(_key) ?? [])
        .map(ShoppingItem.decode)
        .toList();
    var changed = false;
    final memory = await ProductMemoryStore().load();
    for (final item in items) {
      final key = normalizedProductName(item.name);
      final remembered = memory[key];
      if (remembered != null && item.category != remembered.category) {
        item.category = remembered.category;
        changed = true;
      } else if (item.category == GroceryCategory.other) {
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
      final wasCompleted =
          current.checked || current.reconciledReceiptId != null;
      current.quantity =
          wasCompleted ? item.quantity : current.quantity + item.quantity;
      current.checked = false;
      current.completedAt = null;
      current.reconciledReceiptId = null;
      current.purchasedName = null;
      current.actualUnitPrice = null;
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

  Future<void> applyReconciliation({
    required Receipt receipt,
    required List<String> plannedItemIds,
    required Map<String, int> assignments,
  }) async {
    final items = await load();
    final plannedIds = plannedItemIds.toSet();
    for (final item in items.where((item) => plannedIds.contains(item.id))) {
      final receiptIndex = assignments[item.id];
      if (receiptIndex == null ||
          receiptIndex < 0 ||
          receiptIndex >= receipt.items.length) {
        item.checked = false;
        item.completedAt = null;
        item.reconciledReceiptId = null;
        item.purchasedName = null;
        item.actualUnitPrice = null;
        item.note = item.note.toLowerCase().contains('missed')
            ? item.note
            : 'Missed in the last reconciled shopping trip.';
        item.remindAt ??= DateTime.now().add(const Duration(days: 1));
        continue;
      }
      final purchased = receipt.items[receiptIndex];
      item.checked = true;
      item.completedAt = receipt.purchasedAt;
      item.reconciledReceiptId = receipt.id;
      item.purchasedName = purchased.name;
      if (item.note.toLowerCase().contains('missed')) item.note = '';
      item.remindAt = null;
      item.actualUnitPrice = purchased.unitPrice > 0
          ? purchased.unitPrice
          : purchased.quantity > 0
              ? purchased.total / purchased.quantity
              : purchased.total;
    }
    await saveAll(items);
  }
}
