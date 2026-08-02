import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/services/receipt_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saves, replaces and deletes an on-device receipt', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReceiptStore();
    final receipt = Receipt(
      id: 'saved-1',
      store: 'Fresh Mart',
      purchasedAt: DateTime(2026, 8, 2),
      printedTotal: 60,
      items: [
        ReceiptItem(
          name: 'Milk',
          quantity: 2,
          unitPrice: 30,
          discount: 0,
          confidence: 1,
        ),
      ],
    );

    await store.save(receipt);
    receipt.store = 'Fresh Mart Updated';
    await store.save(receipt);

    final saved = await store.load();
    expect(saved, hasLength(1));
    expect(saved.single.store, 'Fresh Mart Updated');

    await store.delete(receipt.id);
    expect(await store.load(), isEmpty);
  });

  test('reclassifies previously saved Other grocery items once', () async {
    final oldReceipt = Receipt(
      id: 'old-categories',
      store: 'D-Mart',
      purchasedAt: DateTime(2026, 8, 2),
      printedTotal: 464,
      items: [
        ReceiptItem(
          name: 'WHISPER BINDAZZ pads',
          category: GroceryCategory.other,
          quantity: 1,
          unitPrice: 344,
          discount: 0,
          confidence: 1,
        ),
        ReceiptItem(
          name: 'Tetely Classic',
          category: GroceryCategory.other,
          quantity: 1,
          unitPrice: 120,
          discount: 0,
          confidence: 1,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'cartsense_receipts_v1': [oldReceipt.encode()],
    });

    final loaded = await ReceiptStore().load();

    expect(loaded.single.items[0].category, GroceryCategory.sanitaryCare);
    expect(loaded.single.items[1].category, GroceryCategory.teaCoffee);
    final preferences = await SharedPreferences.getInstance();
    final persisted = Receipt.decode(
      preferences.getStringList('cartsense_receipts_v1')!.single,
    );
    expect(persisted.items[0].category, GroceryCategory.sanitaryCare);
    expect(preferences.getInt('cartsense_category_rules_version'), 2);
  });
}
