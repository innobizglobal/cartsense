import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';

class ReceiptStore {
  static const _key = 'cartsense_receipts_v1';

  Future<List<Receipt>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).map(Receipt.decode).toList()
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
  }

  Future<void> save(Receipt receipt) async {
    final prefs = await SharedPreferences.getInstance();
    final receipts = await load();
    receipts.removeWhere((existing) => existing.id == receipt.id);
    receipts.insert(0, receipt);
    await prefs.setStringList(
      _key,
      receipts.map((item) => item.encode()).toList(),
    );
  }

  Future<void> delete(String receiptId) async {
    final prefs = await SharedPreferences.getInstance();
    final receipts = await load();
    receipts.removeWhere((receipt) => receipt.id == receiptId);
    await prefs.setStringList(
      _key,
      receipts.map((receipt) => receipt.encode()).toList(),
    );
  }
}
