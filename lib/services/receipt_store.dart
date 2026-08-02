import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';

class ReceiptStore {
  static const _key = 'cartsense_receipts_v1';
  static const _categoryRulesKey = 'cartsense_category_rules_version';
  static const _categoryRulesVersion = 2;

  Future<List<Receipt>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final receipts =
        (prefs.getStringList(_key) ?? []).map(Receipt.decode).toList();
    if ((prefs.getInt(_categoryRulesKey) ?? 0) < _categoryRulesVersion) {
      var changed = false;
      for (final receipt in receipts) {
        for (final item in receipt.items) {
          if (item.category != GroceryCategory.other) continue;
          final inferred = GroceryCategory.infer(item.name);
          if (inferred != GroceryCategory.other) {
            item.category = inferred;
            changed = true;
          }
        }
      }
      if (changed) {
        await prefs.setStringList(
          _key,
          receipts.map((receipt) => receipt.encode()).toList(),
        );
      }
      await prefs.setInt(_categoryRulesKey, _categoryRulesVersion);
    }
    return receipts..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
  }

  Future<void> save(Receipt receipt) async {
    await _preserveReceiptImage(receipt);
    final prefs = await SharedPreferences.getInstance();
    final receipts = await load();
    receipts.removeWhere((existing) => existing.id == receipt.id);
    receipts.insert(0, receipt);
    await prefs.setStringList(
      _key,
      receipts.map((item) => item.encode()).toList(),
    );
  }

  Future<void> _preserveReceiptImage(Receipt receipt) async {
    final sourcePath = receipt.imagePath;
    if (sourcePath == null || sourcePath.isEmpty) return;
    final source = File(sourcePath);
    if (!await source.exists()) return;

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}receipt-images',
    );
    await directory.create(recursive: true);
    final lower = sourcePath.toLowerCase();
    final extension = lower.endsWith('.png')
        ? '.png'
        : lower.endsWith('.webp')
            ? '.webp'
            : '.jpg';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${receipt.id}$extension',
    );
    if (source.absolute.path != destination.absolute.path) {
      await source.copy(destination.path);
      receipt.imagePath = destination.path;
    }
  }

  Future<void> delete(String receiptId) async {
    final prefs = await SharedPreferences.getInstance();
    final receipts = await load();
    final removedImages = receipts
        .where((receipt) => receipt.id == receiptId)
        .map((receipt) => receipt.imagePath)
        .whereType<String>()
        .toList();
    receipts.removeWhere((receipt) => receipt.id == receiptId);
    await prefs.setStringList(
      _key,
      receipts.map((receipt) => receipt.encode()).toList(),
    );
    if (removedImages.isNotEmpty) {
      final documents = await getApplicationDocumentsDirectory();
      final imageRoot = Directory(
        '${documents.path}${Platform.pathSeparator}receipt-images',
      ).absolute.path;
      for (final path in removedImages) {
        final image = File(path);
        if (image.absolute.path.startsWith(
              '$imageRoot${Platform.pathSeparator}',
            ) &&
            await image.exists()) {
          await image.delete();
        }
      }
    }
  }
}
