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
}
