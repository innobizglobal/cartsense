import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/receipt.dart';
import '../models/shopping_item.dart';
import 'auth_service.dart';
import 'family_profile_store.dart';

class CartSenseCloudSyncService {
  CartSenseCloudSyncService._();

  static final instance = CartSenseCloudSyncService._();

  static const _receiptsKey = 'cartsense_receipts_v1';
  static const _shoppingKey = 'cartsense_shopping_list_v1';
  static const _familyProfileKey = 'cartsense_family_profile_v1';
  static const _budgetKey = 'cartsense_monthly_budget_v1';
  static const _languageKey = 'cartsense_language_code_v1';
  static const _lastSyncKey = 'cartsense_cloud_last_sync_v1';

  bool _syncing = false;

  bool get canSync =>
      CartSenseAuthService.isConfigured &&
      CartSenseAuthService.instance.currentUser != null &&
      CartSenseAuthService.instance.client != null;

  Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastSyncKey) ?? '');
  }

  Future<void> syncNow() async {
    if (!canSync || _syncing) return;
    _syncing = true;
    try {
      await _pullFromCloud();
      await _pushAllLocal();
      await _markSynced();
    } on Object {
      // Sync should never break shopping, scanning or saved phone data.
    } finally {
      _syncing = false;
    }
  }

  void syncInBackground() {
    if (!canSync || _syncing) return;
    unawaited(syncNow());
  }

  Future<void> pushReceipt(Receipt receipt) async {
    if (!canSync) return;
    try {
      final user = CartSenseAuthService.instance.currentUser!;
      final client = CartSenseAuthService.instance.client!;
      await client.from('cartsense_receipts').upsert({
        'user_id': user.id,
        'receipt_id': receipt.id,
        'store': receipt.store,
        'purchased_at': receipt.purchasedAt.toIso8601String(),
        'total': receipt.printedTotal > 0
            ? receipt.printedTotal
            : receipt.calculatedTotal,
        'payload': receipt.toJson(),
        'deleted_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _markSynced();
    } on Object {
      // Missing tables or offline network are safe; local data remains saved.
    }
  }

  Future<void> deleteReceipt(String receiptId) async {
    if (!canSync) return;
    try {
      final user = CartSenseAuthService.instance.currentUser!;
      final client = CartSenseAuthService.instance.client!;
      await client.from('cartsense_receipts').upsert({
        'user_id': user.id,
        'receipt_id': receiptId,
        'payload': <String, dynamic>{},
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _markSynced();
    } on Object {
      // Local delete already happened; retry can occur on a later sync.
    }
  }

  Future<void> pushShoppingList(List<ShoppingItem> items) async {
    if (!canSync) return;
    try {
      final user = CartSenseAuthService.instance.currentUser!;
      final client = CartSenseAuthService.instance.client!;
      final activeIds = items.map((item) => item.id).toSet();
      final remote = await client
          .from('cartsense_shopping_items')
          .select('item_id')
          .eq('user_id', user.id);
      final existingIds = (remote as List)
          .map((row) => (row as Map)['item_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final item in items) {
        await client.from('cartsense_shopping_items').upsert({
          'user_id': user.id,
          'item_id': item.id,
          'name': item.name,
          'checked': item.checked,
          'payload': item.toJson(),
          'deleted_at': null,
          'updated_at': now,
        });
      }
      for (final removedId in existingIds.difference(activeIds)) {
        await client.from('cartsense_shopping_items').upsert({
          'user_id': user.id,
          'item_id': removedId,
          'payload': <String, dynamic>{},
          'deleted_at': now,
          'updated_at': now,
        });
      }
      await _markSynced();
    } on Object {
      // Shopping list stays saved on this phone if cloud is unavailable.
    }
  }

  Future<void> pushProfileAndSettings() async {
    if (!canSync) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final profile = await FamilyProfileStore().load();
      final user = CartSenseAuthService.instance.currentUser!;
      final client = CartSenseAuthService.instance.client!;
      await client.from('cartsense_user_settings').upsert({
        'user_id': user.id,
        'payload': {
          'familyProfile': profile.toJson(),
          'monthlyBudget': prefs.getDouble(_budgetKey) ?? 0,
          'languageCode': prefs.getString(_languageKey) ?? 'en',
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _markSynced();
    } on Object {
      // Settings stay saved locally if cloud is unavailable.
    }
  }

  Future<void> _pullFromCloud() async {
    final user = CartSenseAuthService.instance.currentUser;
    final client = CartSenseAuthService.instance.client;
    if (user == null || client == null) return;

    final prefs = await SharedPreferences.getInstance();
    await _mergeReceipts(client, user.id, prefs);
    await _mergeShoppingItems(client, user.id, prefs);
    await _mergeSettings(client, user.id, prefs);
  }

  Future<void> _pushAllLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final receipts = (prefs.getStringList(_receiptsKey) ?? [])
        .map((value) => Receipt.decode(value))
        .toList();
    for (final receipt in receipts) {
      await pushReceipt(receipt);
    }
    final shoppingItems = (prefs.getStringList(_shoppingKey) ?? [])
        .map((value) => ShoppingItem.decode(value))
        .toList();
    await pushShoppingList(shoppingItems);
    await pushProfileAndSettings();
  }

  Future<void> _mergeReceipts(
    SupabaseClient client,
    String userId,
    SharedPreferences prefs,
  ) async {
    final rows = await client
        .from('cartsense_receipts')
        .select('receipt_id,payload,deleted_at')
        .eq('user_id', userId);
    final local = <String, Receipt>{
      for (final raw in prefs.getStringList(_receiptsKey) ?? [])
        Receipt.decode(raw).id: Receipt.decode(raw),
    };
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final receiptId = map['receipt_id']?.toString() ?? '';
      if (receiptId.isEmpty) continue;
      if (map['deleted_at'] != null) {
        local.remove(receiptId);
        continue;
      }
      final payload = map['payload'];
      if (payload is Map) {
        final receipt = Receipt.fromJson(Map<String, dynamic>.from(payload));
        local[receipt.id] = receipt;
      }
    }
    final merged = local.values.toList()
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    await prefs.setStringList(
      _receiptsKey,
      merged.map((receipt) => receipt.encode()).toList(),
    );
  }

  Future<void> _mergeShoppingItems(
    SupabaseClient client,
    String userId,
    SharedPreferences prefs,
  ) async {
    final rows = await client
        .from('cartsense_shopping_items')
        .select('item_id,payload,deleted_at')
        .eq('user_id', userId);
    final local = <String, ShoppingItem>{
      for (final raw in prefs.getStringList(_shoppingKey) ?? [])
        ShoppingItem.decode(raw).id: ShoppingItem.decode(raw),
    };
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final itemId = map['item_id']?.toString() ?? '';
      if (itemId.isEmpty) continue;
      if (map['deleted_at'] != null) {
        local.remove(itemId);
        continue;
      }
      final payload = map['payload'];
      if (payload is Map) {
        final item = ShoppingItem.fromJson(Map<String, dynamic>.from(payload));
        local[item.id] = item;
      }
    }
    final merged = local.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await prefs.setStringList(
      _shoppingKey,
      merged.map((item) => item.encode()).toList(),
    );
  }

  Future<void> _mergeSettings(
    SupabaseClient client,
    String userId,
    SharedPreferences prefs,
  ) async {
    final rows = await client
        .from('cartsense_user_settings')
        .select('payload')
        .eq('user_id', userId)
        .limit(1);
    if ((rows as List).isEmpty) return;
    final row = Map<String, dynamic>.from(rows.first as Map);
    final payload = row['payload'];
    if (payload is! Map) return;
    final settings = Map<String, dynamic>.from(payload);
    final family = settings['familyProfile'];
    if (family is Map) {
      await prefs.setString(
        _familyProfileKey,
        jsonEncode(
          FamilyProfile.fromJson(Map<String, dynamic>.from(family)).toJson(),
        ),
      );
    }
    final monthlyBudget = settings['monthlyBudget'];
    if (monthlyBudget is num) {
      await prefs.setDouble(_budgetKey, monthlyBudget.toDouble());
    }
    final languageCode = settings['languageCode']?.toString();
    if (languageCode != null && languageCode.isNotEmpty) {
      await prefs.setString(_languageKey, languageCode);
    }
  }

  Future<void> _markSynced() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }
}
