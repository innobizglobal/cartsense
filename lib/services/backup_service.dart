import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartSenseBackupService {
  static const version = 1;
  static const _keys = [
    'cartsense_receipts_v1',
    'cartsense_shopping_list_v1',
    'cartsense_product_memory_v1',
    'cartsense_monthly_budget_v1',
    'cartsense_ai_consent',
    'cartsense_category_rules_version',
  ];

  Future<Map<String, dynamic>> buildBackup() async {
    final preferences = await SharedPreferences.getInstance();
    final data = <String, Object?>{};
    for (final key in _keys) {
      if (!preferences.containsKey(key)) continue;
      final value = preferences.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double ||
          value is List<String>) {
        data[key] = value;
      }
    }
    return {
      'app': 'CartSense',
      'version': version,
      'createdAt': DateTime.now().toIso8601String(),
      'data': data,
    };
  }

  Future<String> backupText() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(await buildBackup());
  }

  Future<File> writeBackupFile() async {
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${directory.path}/CartSense_Backup_$stamp.json');
    await file.writeAsString(await backupText());
    return file;
  }

  Future<void> shareBackup() async {
    final file = await writeBackupFile();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      text: 'CartSense backup file',
    );
  }

  Future<int> restoreFromText(String source) async {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    if (decoded['app'] != 'CartSense' || decoded['data'] is! Map) {
      throw const FormatException('This is not a CartSense backup file.');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    final preferences = await SharedPreferences.getInstance();
    var restored = 0;
    for (final entry in data.entries) {
      if (!_keys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is String) {
        await preferences.setString(entry.key, value);
      } else if (value is bool) {
        await preferences.setBool(entry.key, value);
      } else if (value is int) {
        await preferences.setInt(entry.key, value);
      } else if (value is double) {
        await preferences.setDouble(entry.key, value);
      } else if (value is num) {
        await preferences.setDouble(entry.key, value.toDouble());
      } else if (value is List) {
        await preferences.setStringList(
          entry.key,
          value.map((item) => item.toString()).toList(),
        );
      } else {
        continue;
      }
      restored += 1;
    }
    return restored;
  }
}
