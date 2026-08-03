import 'dart:convert';
import 'package:cartsense_lite/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('exports and restores CartSense backup data', () async {
    SharedPreferences.setMockInitialValues({
      'cartsense_receipts_v1': ['receipt-json'],
      'cartsense_shopping_list_v1': ['shopping-json'],
      'cartsense_product_memory_v1': ['memory-json'],
      'cartsense_monthly_budget_v1': 5000.0,
      'cartsense_ai_consent': true,
    });
    final service = CartSenseBackupService();

    final text = await service.backupText();
    final decoded = jsonDecode(text) as Map<String, dynamic>;

    expect(decoded['app'], 'CartSense');
    expect((decoded['data'] as Map)['cartsense_ai_consent'], isTrue);

    SharedPreferences.setMockInitialValues({});
    final restored = await service.restoreFromText(text);
    final preferences = await SharedPreferences.getInstance();

    expect(restored, greaterThanOrEqualTo(5));
    expect(
        preferences.getStringList('cartsense_receipts_v1'), ['receipt-json']);
    expect(preferences.getStringList('cartsense_shopping_list_v1'), [
      'shopping-json',
    ]);
    expect(preferences.getStringList('cartsense_product_memory_v1'), [
      'memory-json',
    ]);
    expect(preferences.getDouble('cartsense_monthly_budget_v1'), 5000);
    expect(preferences.getBool('cartsense_ai_consent'), isTrue);
  });

  test('rejects non-CartSense restore text', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      () => CartSenseBackupService().restoreFromText('{"app":"Other"}'),
      throwsFormatException,
    );
  });
}
