import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/models/shopping_item.dart';
import 'package:cartsense_lite/services/product_memory_store.dart';
import 'package:cartsense_lite/services/shopping_list_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('learns corrected receipt categories and applies them later', () async {
    SharedPreferences.setMockInitialValues({});
    final memory = ProductMemoryStore();
    final corrected = ReceiptItem(
      name: 'Whisper Bindazz Pads',
      quantity: 1,
      unitPrice: 88,
      discount: 0,
      confidence: 1,
      category: GroceryCategory.sanitaryCare,
    );

    await memory.rememberItem(
      scannedName: 'NHISPER BINDAZZ-ngs',
      corrected: corrected,
    );

    final receipt = Receipt(
      id: 'new',
      store: 'DMart',
      purchasedAt: DateTime(2026, 8, 3),
      printedTotal: 88,
      items: [
        ReceiptItem(
          name: 'NHISPER BINDAZZ-ngs',
          quantity: 1,
          unitPrice: 88,
          discount: 0,
          confidence: .42,
          category: GroceryCategory.other,
        ),
      ],
    );

    final changed = await memory.applyToReceipt(receipt);

    expect(changed, isTrue);
    expect(receipt.items.single.category, GroceryCategory.sanitaryCare);
    expect(receipt.items.single.confidence, greaterThanOrEqualTo(.86));
  });

  test('shopping list uses remembered category for matching products',
      () async {
    SharedPreferences.setMockInitialValues({});
    await ProductMemoryStore().rememberItem(
      scannedName: 'Tetely Classic',
      corrected: ReceiptItem(
        name: 'Tetley Classic Tea',
        quantity: 1,
        unitPrice: 90,
        discount: 0,
        confidence: 1,
        category: GroceryCategory.teaCoffee,
      ),
    );
    final store = ShoppingListStore();
    await store.add(ShoppingItem(
      id: 'tea',
      name: 'Tetely Classic',
      quantity: 1,
      category: GroceryCategory.other,
      expectedUnitPrice: 90,
      bestUnitPrice: 90,
      bestStore: 'DMart',
      latestStore: 'DMart',
      createdAt: DateTime(2026, 8, 3),
    ));

    final items = await store.load();

    expect(items.single.category, GroceryCategory.teaCoffee);
  });
}
