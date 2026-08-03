import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';

class ProductMemoryEntry {
  const ProductMemoryEntry({
    required this.key,
    required this.displayName,
    required this.category,
    required this.learnedAt,
    required this.useCount,
  });

  final String key;
  final String displayName;
  final String category;
  final DateTime learnedAt;
  final int useCount;

  Map<String, dynamic> toJson() => {
        'key': key,
        'displayName': displayName,
        'category': category,
        'learnedAt': learnedAt.toIso8601String(),
        'useCount': useCount,
      };

  factory ProductMemoryEntry.fromJson(Map<String, dynamic> json) =>
      ProductMemoryEntry(
        key: json['key']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        category: json['category']?.toString() ?? GroceryCategory.other,
        learnedAt: DateTime.tryParse(json['learnedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      );
}

class ProductMemoryStore {
  static const _key = 'cartsense_product_memory_v1';

  Future<Map<String, ProductMemoryEntry>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final entries = <String, ProductMemoryEntry>{};
    for (final value in preferences.getStringList(_key) ?? const []) {
      try {
        final entry = ProductMemoryEntry.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
        if (entry.key.isNotEmpty) entries[entry.key] = entry;
      } catch (_) {
        // Ignore older/corrupt memory rows rather than blocking app startup.
      }
    }
    return entries;
  }

  Future<void> saveAll(Map<String, ProductMemoryEntry> entries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key,
      entries.values.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }

  Future<void> rememberItem({
    required String scannedName,
    required ReceiptItem corrected,
  }) async {
    final keys = {
      normalizedProductName(scannedName),
      normalizedProductName(corrected.name),
    }.where((key) => key.length > 1);
    if (keys.isEmpty || corrected.name.trim().isEmpty) return;

    final entries = await load();
    for (final key in keys) {
      final existing = entries[key];
      entries[key] = ProductMemoryEntry(
        key: key,
        displayName: corrected.name.trim(),
        category: corrected.category,
        learnedAt: DateTime.now(),
        useCount: (existing?.useCount ?? 0) + 1,
      );
    }
    await saveAll(entries);
  }

  Future<bool> applyToReceipt(Receipt receipt) async {
    final entries = await load();
    if (entries.isEmpty) return false;
    var changed = false;
    for (final item in receipt.items) {
      final entry = _match(entries, item.name);
      if (entry == null) continue;
      if (item.category == GroceryCategory.other ||
          item.category != entry.category) {
        item.category = entry.category;
        changed = true;
      }
      if (item.confidence < .86) {
        item.confidence = .86;
        changed = true;
      }
    }
    return changed;
  }

  ProductMemoryEntry? _match(
    Map<String, ProductMemoryEntry> entries,
    String scannedName,
  ) {
    final key = normalizedProductName(scannedName);
    if (key.length < 2) return null;
    final exact = entries[key];
    if (exact != null) return exact;

    ProductMemoryEntry? best;
    var bestScore = 0;
    final tokens = key.split(' ').where((token) => token.length > 2).toSet();
    for (final entry in entries.values) {
      if (entry.key.contains(key) || key.contains(entry.key)) {
        return entry;
      }
      final entryTokens =
          entry.key.split(' ').where((token) => token.length > 2).toSet();
      final score = tokens.intersection(entryTokens).length;
      if (score > bestScore && score >= 2) {
        best = entry;
        bestScore = score;
      } else if (best == null &&
          score == 1 &&
          tokens.union(entryTokens).any((token) => token.length >= 6) &&
          tokens.intersection(entryTokens).first.length >= 6) {
        best = entry;
        bestScore = score;
      }
    }
    return best;
  }
}
