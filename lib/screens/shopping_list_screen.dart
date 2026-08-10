import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_catalog.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../models/shopping_item.dart';
import '../services/budget_store.dart';
import '../services/ai_receipt_service.dart';
import '../services/family_profile_store.dart';
import '../services/language_store.dart';
import '../services/price_intelligence_api.dart';
import '../services/shopping_list_store.dart';
import '../services/shopping_reminder_service.dart';
import '../services/voice_input_service.dart';
import 'product_master_screen.dart';
import '../theme/cartsense_theme.dart';
import '../widgets/app_footer_nav.dart';
import '../widgets/category_icon.dart';

const _green = CartSenseColors.primary;
const _lime = CartSenseColors.accent;
const _ivory = CartSenseColors.background;

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({
    super.key,
    required this.receipts,
    this.activeShoppingCount = 0,
    this.onOpenInsights,
  });

  final List<Receipt> receipts;
  final int activeShoppingCount;
  final VoidCallback? onOpenInsights;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final store = ShoppingListStore();
  final budgetStore = BudgetStore();
  final queryController = TextEditingController();
  List<ShoppingItem> items = [];
  List<CatalogProduct> searchResults = [];
  bool loading = true;
  double monthlyBudget = 0;
  FamilyProfile familyProfile = FamilyProfile.empty;
  String languageCode = 'en';

  late final ProductCatalog catalog =
      ProductCatalog.fromReceipts(widget.receipts);
  late final SavingsIntelligence intelligence =
      SavingsIntelligence.fromReceipts(widget.receipts);

  List<ShoppingItem> get activeItems =>
      items.where((item) => !item.checked).toList();
  List<ShoppingItem> get displayItems => [
        ...activeItems,
        ...items.where((item) => item.checked),
      ];
  double get estimatedTotal =>
      activeItems.fold(0, (total, item) => total + item.estimatedTotal);
  double get possibleSaving =>
      activeItems.fold(0, (total, item) => total + item.possibleSaving);

  @override
  void initState() {
    super.initState();
    _load();
    _loadBudget();
    _loadFamilyProfile();
    _loadLanguage();
  }

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await store.load();
    if (mounted) {
      setState(() {
        items = saved;
        loading = false;
      });
    }
  }

  Future<void> _loadBudget() async {
    final budget = await budgetStore.load();
    if (mounted) setState(() => monthlyBudget = budget);
  }

  Future<void> _loadFamilyProfile() async {
    final profile = await FamilyProfileStore().load();
    if (mounted) setState(() => familyProfile = profile);
  }

  Future<void> _loadLanguage() async {
    final language = await LanguageStore().load();
    if (mounted) setState(() => languageCode = language.code);
  }

  String t(String key) => appText(languageCode, key);

  void _search(String value) {
    setState(() => searchResults = catalog.search(value));
  }

  Future<void> _openEditor({
    ShoppingItem? existing,
    CatalogProduct? product,
    FrequentProduct? frequent,
    String initialName = '',
  }) async {
    final frequentProduct = frequent == null
        ? null
        : CatalogProduct(
            name: frequent.name,
            category: frequent.category,
            latestUnitPrice: frequent.latestPrice,
            bestUnitPrice: frequent.bestPrice,
            latestStore: '',
            bestStore: frequent.bestStore,
            purchaseCount: frequent.purchaseCount,
            lastPurchased: frequent.lastPurchased,
          );
    final edited = await showDialog<ShoppingItem>(
      context: context,
      builder: (context) => _ShoppingItemEditor(
        catalog: catalog,
        existing: existing,
        initialProduct: product ?? frequentProduct,
        initialName: initialName,
      ),
    );
    if (edited == null) return;

    if (existing == null) {
      await store.add(edited);
    } else {
      await store.update(edited);
    }
    if ((edited.salePrice ?? edited.expectedUnitPrice) > 0) {
      try {
        await PriceIntelligenceApi().uploadShelfPrice(edited);
      } on Object {
        // Keep list saving fast and reliable even when online price sync fails.
      }
    }
    await _load();
    final storedItem = existing == null
        ? items.firstWhere(
            (item) =>
                normalizedProductName(item.name) ==
                normalizedProductName(edited.name),
            orElse: () => edited,
          )
        : edited;
    var reminderAllowed = true;
    if (existing?.remindAt != null && storedItem.remindAt == null) {
      await ShoppingReminderService.instance.cancel(existing!);
    } else if (storedItem.remindAt != null) {
      reminderAllowed =
          await ShoppingReminderService.instance.schedule(storedItem);
    }
    queryController.clear();
    if (mounted) {
      setState(() => searchResults = []);
      final message = !reminderAllowed
          ? '${edited.name} was saved. Enable notifications in Android settings for its reminder.'
          : existing == null
              ? '${edited.name} added as ${categoryText(languageCode, edited.category)}.'
              : '${edited.name} updated.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  ShoppingItem _itemFromProduct(CatalogProduct product) => ShoppingItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: product.name,
        quantity: 1,
        category: product.category,
        expectedUnitPrice: product.latestUnitPrice,
        bestUnitPrice: product.bestUnitPrice,
        bestStore: product.bestStore,
        latestStore: product.latestStore,
        createdAt: DateTime.now(),
      );

  ShoppingItem _itemFromFrequent(FrequentProduct product) => ShoppingItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: product.name,
        quantity: 1,
        category: product.category,
        expectedUnitPrice: product.latestPrice,
        bestUnitPrice: product.bestPrice,
        bestStore: product.bestStore,
        latestStore: product.bestStore,
        note: 'Suggested from your repeat purchases.',
        createdAt: DateTime.now(),
      );

  Future<void> _addQuick(ShoppingItem item) async {
    await store.add(item);
    await _load();
    queryController.clear();
    if (!mounted) return;
    setState(() => searchResults = []);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${item.name} added to your shopping list.'),
    ));
  }

  Future<void> _addMonthlyEssentials(List<ShoppingItem> suggestions) async {
    for (final item in suggestions) {
      await store.add(item);
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${suggestions.length} monthly essentials added.'),
    ));
  }

  List<ShoppingItem> _monthlyEssentials() {
    final now = DateTime.now();
    if (now.day < 20 && activeItems.isNotEmpty) return const [];
    final activeKeys =
        activeItems.map((item) => normalizedProductName(item.name)).toSet();
    final previousMonth = DateTime(now.year, now.month - 1);
    final monthlyStapleCategories = {
      GroceryCategory.pantry,
      GroceryCategory.cookingOils,
      GroceryCategory.dairy,
      GroceryCategory.household,
      GroceryCategory.personalCare,
      GroceryCategory.sanitaryCare,
      GroceryCategory.babyCare,
      GroceryCategory.teaCoffee,
    };
    final products = <String, CatalogProduct>{};
    for (final product in catalog.products) {
      if (activeKeys.contains(product.key)) continue;
      final boughtPreviousMonth =
          product.lastPurchased.year == previousMonth.year &&
              product.lastPurchased.month == previousMonth.month;
      final repeated = product.purchaseCount >= 2;
      if (!boughtPreviousMonth && !repeated) continue;
      if (!monthlyStapleCategories.contains(product.category)) continue;
      products.putIfAbsent(product.key, () => product);
    }
    final scale = familyProfile.isConfigured ? familyProfile.householdScale : 1;
    return products.values.take(8).map((product) {
      final quantity =
          scale >= 6 && product.category != GroceryCategory.sanitaryCare
              ? 2.0
              : 1.0;
      return ShoppingItem(
        id: 'monthly-${DateTime.now().microsecondsSinceEpoch}-${product.key}',
        name: product.name,
        quantity: quantity,
        category: product.category,
        expectedUnitPrice: product.latestUnitPrice,
        bestUnitPrice: product.bestUnitPrice,
        bestStore: product.bestStore,
        latestStore: product.latestStore,
        note: familyProfile.isConfigured
            ? 'Monthly suggestion for ${familyProfile.members} family members.'
            : 'Monthly suggestion from past receipts.',
        sourceReceiptId: null,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  Future<void> _addFromPreviousBills() async {
    final alreadyPlanned = items
        .where((item) => !item.checked)
        .map((item) => normalizedProductName(item.name))
        .toSet();
    final products = catalog.products
        .where((product) => !alreadyPlanned.contains(product.key))
        .take(120)
        .toList();
    if (products.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Scan and save a bill first, then products appear here.'),
      ));
      return;
    }
    final selected = await showModalBottomSheet<List<CatalogProduct>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PreviousBillProductPicker(
        products: products,
        languageCode: languageCode,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    for (final product in selected) {
      await store.add(_itemFromProduct(product));
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${selected.length} products added from previous bills.'),
    ));
  }

  Future<void> _toggle(ShoppingItem item, bool checked) async {
    setState(() {
      item.checked = checked;
      item.completedAt = checked ? DateTime.now() : null;
      if (!checked) {
        item.reconciledReceiptId = null;
        item.purchasedName = null;
        item.actualUnitPrice = null;
      }
    });
    await store.update(item);
    if (checked) {
      await ShoppingReminderService.instance.cancel(item);
    } else if (item.remindAt != null) {
      await ShoppingReminderService.instance.schedule(item);
    }
  }

  Future<void> _delete(ShoppingItem item) async {
    await ShoppingReminderService.instance.cancel(item);
    setState(() => items.removeWhere((value) => value.id == item.id));
    await store.saveAll(items);
  }

  Future<void> _removeChecked() async {
    final completed = items.where((item) => item.checked).toList();
    for (final item in completed) {
      await ShoppingReminderService.instance.cancel(item);
    }
    setState(() => items.removeWhere((item) => item.checked));
    await store.saveAll(items);
  }

  Future<void> _shareList() async {
    if (activeItems.isEmpty) return;
    final lines = <String>[
      'CartSense shopping list',
      '',
      ...activeItems.map((item) {
        final price = item.expectedUnitPrice > 0
            ? ' — about ₹${item.estimatedTotal.toStringAsFixed(2)}'
            : '';
        final storeText = item.bestStore.isNotEmpty
            ? ' (best seen at ${item.bestStore})'
            : '';
        return '☐ ${item.quantity.g} × ${item.name}$price$storeText';
      }),
      '',
      'Estimated basket: ₹${estimatedTotal.toStringAsFixed(2)}',
    ];
    await Share.share(
      lines.join('\n'),
      subject: 'CartSense shopping list',
    );
  }

  Future<void> _openTripMode() async {
    final scanNow = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ShoppingTripModeScreen(
          items: activeItems,
          catalog: catalog,
          onToggle: _toggle,
          onEdit: (item) => _openEditor(existing: item),
        ),
      ),
    );
    await _load();
    if (scanNow == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _openProductMaster() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductMasterScreen(
        receipts: widget.receipts,
        activeShoppingCount: activeItems.length,
        onOpenShoppingList: () {},
        onOpenInsights: widget.onOpenInsights,
      ),
    ));
    await _load();
  }

  Map<String, List<ShoppingItem>> get _storePlan {
    final plan = <String, List<ShoppingItem>>{};
    for (final item in activeItems) {
      final storeName =
          item.bestStore.isEmpty ? 'Price needed' : item.bestStore;
      plan.putIfAbsent(storeName, () => []).add(item);
    }
    return plan;
  }

  List<ProductPriceInsight> _priceWatchItems() {
    final activeKeys = activeItems
        .map((item) => normalizedProductName(item.name))
        .where((key) => key.length > 1)
        .toSet();
    return intelligence.priceRises
        .where((insight) =>
            activeKeys.contains(normalizedProductName(insight.name)))
        .take(4)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final dueSuggestions = intelligence.frequentProducts
        .where((suggestion) =>
            suggestion.isDueAt(DateTime.now()) &&
            !items.any((current) =>
                normalizedProductName(current.name) ==
                normalizedProductName(suggestion.name)))
        .take(5)
        .toList();
    final dueReminders = activeItems
        .where((item) => item.isReminderDue(DateTime.now()))
        .toList();
    final recognizedCategory = queryController.text.trim().isEmpty
        ? null
        : GroceryCategory.infer(queryController.text);
    final monthSpend = intelligence.currentMonthTotal;
    final projectedMonthSpend = monthSpend + estimatedTotal;
    final budgetRemaining =
        monthlyBudget <= 0 ? 0.0 : monthlyBudget - projectedMonthSpend;
    final missedItems = activeItems
        .where((item) => item.note.toLowerCase().contains('missed'))
        .toList();
    final priceWatch = _priceWatchItems();
    final monthlyEssentials = _monthlyEssentials();

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        title: Text(t('shoppingAssistant')),
        actions: [
          IconButton(
            tooltip: 'Product master',
            onPressed: _openProductMaster,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'Share list',
            onPressed: activeItems.isEmpty ? null : _shareList,
            icon: const Icon(Icons.share_outlined),
          ),
          if (items.any((item) => item.checked))
            PopupMenuButton<String>(
              tooltip: 'List options',
              onSelected: (value) {
                if (value == 'clear') _removeChecked();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cleaning_services_outlined),
                    title: Text('Clear purchased'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              children: [
                Card(
                  color: _green,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('estimatedBasket'),
                                  style:
                                      const TextStyle(color: Colors.white70)),
                              Text(
                                '₹${estimatedTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${activeItems.length} remaining · ${items.where((item) => item.checked).length} purchased',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              const Row(
                                children: [
                                  Icon(Icons.cloud_done_outlined,
                                      size: 16, color: _lime),
                                  SizedBox(width: 5),
                                  Text(
                                    'Saved automatically on this device',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (monthlyBudget > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  budgetRemaining >= 0
                                      ? 'After this trip: â‚¹${budgetRemaining.toStringAsFixed(0)} monthly budget left'
                                      : 'After this trip: â‚¹${budgetRemaining.abs().toStringAsFixed(0)} over monthly budget',
                                  style: TextStyle(
                                    color: budgetRemaining >= 0
                                        ? Colors.white70
                                        : Colors.orange.shade100,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (possibleSaving > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(t('possibleSaving'),
                                  style:
                                      const TextStyle(color: Colors.white70)),
                              Text(
                                '₹${possibleSaving.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: _lime,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (activeItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openTripMode,
                          icon: const Icon(Icons.local_grocery_store_outlined),
                          label: Text(t('startTrip')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareList,
                          icon: const Icon(Icons.ios_share_outlined),
                          label: Text(t('shareList')),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (activeItems.isNotEmpty || dueSuggestions.isNotEmpty) ...[
                  Card(
                    color: CartSenseColors.surfaceMuted,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, color: _green),
                              const SizedBox(width: 8),
                              Text(
                                t('smartTripAssistant'),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _smartLine(
                            Icons.shopping_basket_outlined,
                            activeItems.isEmpty
                                ? 'Add products to plan your next store trip.'
                                : '${activeItems.length} products planned, about ₹${estimatedTotal.toStringAsFixed(0)}.',
                          ),
                          if (monthlyBudget > 0)
                            _smartLine(
                              budgetRemaining >= 0
                                  ? Icons.verified_outlined
                                  : Icons.warning_amber_rounded,
                              budgetRemaining >= 0
                                  ? 'After this trip, about ₹${budgetRemaining.toStringAsFixed(0)} remains in your monthly budget.'
                                  : 'This trip may put you ₹${budgetRemaining.abs().toStringAsFixed(0)} over your monthly budget.',
                            ),
                          if (possibleSaving > 0)
                            _smartLine(
                              Icons.savings_outlined,
                              'Possible saving: ₹${possibleSaving.toStringAsFixed(0)} if you buy at best-seen stores.',
                            ),
                          if (dueSuggestions.isNotEmpty)
                            _smartLine(
                              Icons.replay_outlined,
                              '${dueSuggestions.length} usual products may be due again.',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  color: CartSenseColors.surfaceMuted,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('howShoppingAssistant'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _workflowStep(
                          Icons.edit_note_outlined,
                          t('planStep'),
                          t('planStepBody'),
                        ),
                        _workflowStep(
                          Icons.storefront_outlined,
                          t('shopStep'),
                          t('shopStepBody'),
                        ),
                        _workflowStep(
                          Icons.document_scanner_outlined,
                          t('reconcileStep'),
                          t('reconcileStepBody'),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: queryController,
                  onChanged: _search,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _openEditor(initialName: value.trim());
                    }
                  },
                  decoration: InputDecoration(
                    labelText: t('addProductField'),
                    hintText: t('addProductHint'),
                    prefixIcon: const Icon(Icons.add_shopping_cart_outlined),
                    suffixIcon: queryController.text.trim().isEmpty
                        ? IconButton(
                            tooltip: 'Add product',
                            onPressed: _openEditor,
                            icon: const Icon(Icons.add_circle_outline),
                          )
                        : IconButton(
                            tooltip: 'Add this product',
                            onPressed: () => _openEditor(
                              initialName: queryController.text.trim(),
                            ),
                            icon: const Icon(Icons.add_circle, color: _green),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: catalog.products.isEmpty
                            ? null
                            : _addFromPreviousBills,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Add from previous bills'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openProductMaster,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('All products'),
                      ),
                    ),
                  ],
                ),
                if (recognizedCategory != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 18, color: _green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          recognizedCategory == GroceryCategory.other
                              ? 'Choose a matching product below or set its category.'
                              : 'Recognized as $recognizedCategory',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...searchResults.map((product) => Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          onTap: () => _openEditor(product: product),
                          leading: CategoryAvatar(category: product.category),
                          title: Text(product.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            '${product.category} · latest ₹${product.latestUnitPrice.toStringAsFixed(2)} at ${product.latestStore}',
                          ),
                          trailing: product.bestStore == product.latestStore
                              ? IconButton(
                                  tooltip: 'Quick add',
                                  onPressed: () =>
                                      _addQuick(_itemFromProduct(product)),
                                  icon: const Icon(Icons.add_circle_outline),
                                )
                              : Text(
                                  'Best ₹${product.bestUnitPrice.toStringAsFixed(2)}\n${product.bestStore}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 12),
                                ),
                        ),
                      )),
                ] else if (queryController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: CartSenseColors.surfaceMuted,
                    child: ListTile(
                      leading: const Icon(Icons.search_off, color: _green),
                      title: const Text(
                        'No matching saved product',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        'Add "${queryController.text.trim()}" as a new product and choose its category.',
                      ),
                      trailing: TextButton(
                        onPressed: () => _openEditor(
                          initialName: queryController.text.trim(),
                        ),
                        child: const Text('Add'),
                      ),
                    ),
                  ),
                ],
                if (priceWatch.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(Icons.price_change_outlined, 'Price watch'),
                  ...priceWatch.map((insight) => Card(
                        color: CartSenseColors.warning,
                        child: ListTile(
                          leading: const Icon(Icons.trending_up,
                              color: Colors.deepOrange),
                          title: Text(
                            insight.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            'Was ₹${insight.previousPrice!.toStringAsFixed(2)}, now ₹${insight.latestPrice.toStringAsFixed(2)} at ${insight.latestStore}.',
                          ),
                          trailing: Text(
                            '+${insight.priceChangePercent.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )),
                ],
                if (missedItems.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(
                    Icons.notification_important_outlined,
                    'Missed last trip',
                  ),
                  ...missedItems.map((item) => Card(
                        color: CartSenseColors.warning,
                        child: ListTile(
                          leading: CategoryAvatar(category: item.category),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'Still on your list after reconciliation. Pick this first next trip.',
                          ),
                          trailing: TextButton(
                            onPressed: () => _toggle(item, true),
                            child: const Text('Bought'),
                          ),
                        ),
                      )),
                ],
                if (monthlyEssentials.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(
                    Icons.auto_awesome_outlined,
                    'Suggested monthly essentials',
                  ),
                  Card(
                    color: CartSenseColors.success,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CartSense prepared this from previous monthly purchases. Add all, or add only what you need.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ...monthlyEssentials.map((item) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    CategoryAvatar(category: item.category),
                                title: Text(item.name),
                                subtitle: Text(
                                  '${categoryText(languageCode, item.category)} · about ₹${item.estimatedTotal.toStringAsFixed(2)}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Add',
                                  onPressed: () => _addQuick(item),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              )),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _addMonthlyEssentials(monthlyEssentials),
                              icon: const Icon(Icons.playlist_add_check),
                              label: const Text('Add all monthly essentials'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _sectionTitle(Icons.checklist, t('productsToBuy')),
                if (items.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(t('emptyShoppingList')),
                    ),
                  )
                else
                  ...displayItems.map((item) => Card(
                        child: CheckboxListTile(
                          value: item.checked,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) => _toggle(item, value == true),
                          title: Text(
                            '${item.quantity.g} × ${item.name}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              decoration: item.checked
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Text(_itemSubtitle(item)),
                          secondary: PopupMenuButton<String>(
                            tooltip: 'Product actions',
                            onSelected: (value) {
                              if (value == 'edit') {
                                _openEditor(existing: item);
                              } else if (value == 'delete') {
                                _delete(item);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Remove')),
                            ],
                          ),
                        ),
                      )),
                if (dueReminders.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(
                      Icons.notifications_active_outlined, 'Reminders'),
                  ...dueReminders.map((item) => Card(
                        color: CartSenseColors.warning,
                        child: ListTile(
                          leading: CategoryAvatar(category: item.category),
                          title: Text(item.name),
                          subtitle: Text(_reminderText(item.remindAt!)),
                          trailing: TextButton(
                            onPressed: () => _toggle(item, true),
                            child: const Text('Purchased'),
                          ),
                        ),
                      )),
                ],
                if (dueSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(Icons.replay, 'Buy again'),
                  ...dueSuggestions.map((suggestion) => Card(
                        color: CartSenseColors.success,
                        child: ListTile(
                          leading:
                              CategoryAvatar(category: suggestion.category),
                          title: Text(suggestion.name),
                          subtitle: Text(
                            '${suggestion.category} · usually ₹${suggestion.latestPrice.toStringAsFixed(2)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Add to list',
                            onPressed: () =>
                                _addQuick(_itemFromFrequent(suggestion)),
                            icon: const Icon(Icons.add_circle, color: _green),
                          ),
                        ),
                      )),
                ],
                if (_storePlan.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle(Icons.storefront_outlined, 'Store plan'),
                  Card(
                    child: Column(
                      children: _storePlan.entries.map((entry) {
                        final total = entry.value.fold(
                          0.0,
                          (sum, item) =>
                              sum +
                              item.quantity *
                                  (item.bestUnitPrice > 0
                                      ? item.bestUnitPrice
                                      : item.expectedUnitPrice),
                        );
                        return ExpansionTile(
                          title: Text(entry.key,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${entry.value.length} products'),
                          trailing: Text(
                            total > 0 ? '₹${total.toStringAsFixed(2)}' : '—',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          children: entry.value
                              .map((item) => ListTile(
                                    dense: true,
                                    title: Text(
                                        '${item.quantity.g} × ${item.name}'),
                                    trailing: item.bestUnitPrice > 0
                                        ? Text(
                                            '₹${(item.quantity * item.bestUnitPrice).toStringAsFixed(2)}')
                                        : const Text('No price'),
                                  ))
                              .toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Card(
                    color: _green,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Finished shopping?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Scan the checkout bill to compare it with this saved list. Bought items are completed, missed items stay on the list, and extra purchases are shown separately.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _lime,
                              foregroundColor: _green,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Scan bill to reconcile'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: CartSenseFooterNav(
        selectedIndex: 2,
        activeShoppingCount: activeItems.length,
        languageCode: languageCode,
        onDestinationSelected: (index) {
          if (index == 0) {
            Navigator.pop(context, false);
          } else if (index == 1) {
            Navigator.pop(context, true);
          } else if (index == 3) {
            Navigator.pop(context, false);
            widget.onOpenInsights?.call();
          }
        },
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: _green),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );

  Widget _smartLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: _green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(height: 1.25),
              ),
            ),
          ],
        ),
      );

  Widget _workflowStep(
    IconData icon,
    String title,
    String body, {
    bool isLast = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: _green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    body,
                    style: const TextStyle(
                      color: CartSenseColors.textMuted,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  String _itemSubtitle(ShoppingItem item) {
    final parts = <String>[
      categoryText(languageCode, item.category),
      'Added ${_shortDate(item.createdAt)}',
    ];
    if (item.reconciledReceiptId != null) {
      final purchased =
          item.purchasedName == null || item.purchasedName == item.name
              ? 'matched on your bill'
              : 'matched as ${item.purchasedName}';
      final actual = item.actualUnitPrice == null
          ? ''
          : ' at ₹${item.actualUnitPrice!.toStringAsFixed(2)}';
      parts.add('$purchased$actual');
    }
    if (item.expectedUnitPrice > 0) {
      parts.add('estimate ₹${item.estimatedTotal.toStringAsFixed(2)}');
    } else {
      parts.add('price needed');
    }
    if (item.salePrice != null || item.mrp != null) {
      parts.add([
        if (item.salePrice != null)
          'shelf sale ₹${item.salePrice!.toStringAsFixed(2)}',
        if (item.mrp != null) 'MRP ₹${item.mrp!.toStringAsFixed(2)}',
      ].join(' / '));
    }
    if (item.bestStore.isNotEmpty && item.possibleSaving > 0) {
      parts.add(
          'save ₹${item.possibleSaving.toStringAsFixed(2)} at ${item.bestStore}');
    } else if (item.bestStore.isNotEmpty) {
      parts.add('best seen at ${item.bestStore}');
    }
    if (item.remindAt != null) parts.add(_reminderText(item.remindAt!));
    if (item.note.isNotEmpty) parts.add(item.note);
    return parts.join(' · ');
  }

  String _shortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _PreviousBillProductPicker extends StatefulWidget {
  const _PreviousBillProductPicker({
    required this.products,
    required this.languageCode,
  });

  final List<CatalogProduct> products;
  final String languageCode;

  @override
  State<_PreviousBillProductPicker> createState() =>
      _PreviousBillProductPickerState();
}

class _PreviousBillProductPickerState
    extends State<_PreviousBillProductPicker> {
  final selectedKeys = <String>{};
  String query = '';

  List<CatalogProduct> get filtered {
    final needle = normalizedProductName(query);
    if (needle.isEmpty) return widget.products;
    return widget.products
        .where((product) =>
            product.key.contains(needle) ||
            categoryText(widget.languageCode, product.category)
                .toLowerCase()
                .contains(query.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final products = filtered;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add from previous bills',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select products you already bought before. CartSense will reuse the latest price and category.',
                    style: TextStyle(color: CartSenseColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => setState(() => query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search previous products',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  final selected = selectedKeys.contains(product.key);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedKeys.add(product.key);
                        } else {
                          selectedKeys.remove(product.key);
                        }
                      });
                    },
                    secondary: CategoryAvatar(category: product.category),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${categoryText('en', product.category)} · ₹${product.latestUnitPrice.toStringAsFixed(2)} at ${product.latestStore}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: FilledButton.icon(
                onPressed: selectedKeys.isEmpty
                    ? null
                    : () {
                        Navigator.pop(
                          context,
                          widget.products
                              .where((product) =>
                                  selectedKeys.contains(product.key))
                              .toList(),
                        );
                      },
                icon: const Icon(Icons.playlist_add_check),
                label: Text('Add ${selectedKeys.length} selected'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShoppingItemEditor extends StatefulWidget {
  const _ShoppingItemEditor({
    required this.catalog,
    this.existing,
    this.initialProduct,
    this.initialName = '',
  });

  final ProductCatalog catalog;
  final ShoppingItem? existing;
  final CatalogProduct? initialProduct;
  final String initialName;

  @override
  State<_ShoppingItemEditor> createState() => _ShoppingItemEditorState();
}

class _ShoppingItemEditorState extends State<_ShoppingItemEditor> {
  late final TextEditingController name;
  late final TextEditingController quantity;
  late final TextEditingController price;
  late final TextEditingController note;
  late String category;
  late DateTime? remindAt;
  CatalogProduct? matched;
  List<CatalogProduct> matches = [];
  double? shelfMrp;
  double? shelfSalePrice;
  String? shelfPackSize;
  bool scanningShelf = false;
  bool listeningVoice = false;
  String languageCode = 'en';

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    matched = widget.initialProduct;
    name = TextEditingController(
      text: item?.name ?? widget.initialProduct?.name ?? widget.initialName,
    );
    quantity = TextEditingController(text: item?.quantity.g ?? '1');
    final initialPrice =
        item?.expectedUnitPrice ?? widget.initialProduct?.latestUnitPrice ?? 0;
    price = TextEditingController(
      text: initialPrice > 0 ? initialPrice.toStringAsFixed(2) : '',
    );
    note = TextEditingController(text: item?.note ?? '');
    category = item?.category ??
        widget.initialProduct?.category ??
        GroceryCategory.infer(widget.initialName);
    remindAt = item?.remindAt;
    shelfMrp = item?.mrp;
    shelfSalePrice = item?.salePrice;
    matches = widget.catalog.search(name.text, limit: 4);
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final language = await LanguageStore().load();
    if (mounted) setState(() => languageCode = language.code);
  }

  String t(String key) => appText(languageCode, key);

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    price.dispose();
    note.dispose();
    super.dispose();
  }

  void _nameChanged(String value) {
    final exact = widget.catalog.exactMatch(value);
    setState(() {
      matches = widget.catalog.search(value, limit: 4);
      matched = exact;
      category = exact?.category ?? GroceryCategory.infer(value);
      if (exact != null && price.text.trim().isEmpty) {
        price.text = exact.latestUnitPrice.toStringAsFixed(2);
      }
    });
  }

  void _selectProduct(CatalogProduct product) {
    setState(() {
      matched = product;
      name.text = product.name;
      price.text = product.latestUnitPrice.toStringAsFixed(2);
      category = product.category;
      matches = [product];
    });
  }

  Future<void> _listenForProductName() async {
    setState(() => listeningVoice = true);
    try {
      final spoken = await VoiceInputService().listen(
        languageCode: languageCode,
      );
      if (spoken == null || !mounted) return;
      name.text = spoken;
      _nameChanged(spoken);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Heard: $spoken'),
      ));
    } on VoiceInputException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.message),
      ));
    } finally {
      if (mounted) setState(() => listeningVoice = false);
    }
  }

  Future<void> _pickReminder() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: remindAt ?? DateTime.now(),
      helpText: 'When should CartSense remind you?',
    );
    if (selected != null) {
      setState(() => remindAt = DateTime(
            selected.year,
            selected.month,
            selected.day,
            9,
          ));
    }
  }

  Future<void> _scanShelfPrice() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (photo == null) return;
    setState(() => scanningShelf = true);
    try {
      final result = await AiReceiptService().parseShelfPrice(File(photo.path));
      final productName = result.productName.trim();
      final usablePrice = result.salePrice ?? result.mrp;
      setState(() {
        if (productName.isNotEmpty) {
          name.text = productName;
          matched = widget.catalog.exactMatch(productName);
          matches = widget.catalog.search(productName, limit: 4);
          category = matched?.category ?? GroceryCategory.infer(productName);
        }
        if (usablePrice != null && usablePrice > 0) {
          price.text = usablePrice.toStringAsFixed(2);
        }
        shelfMrp = result.mrp;
        shelfSalePrice = result.salePrice;
        shelfPackSize = result.packSize;
      });
      if (!mounted) return;
      final details = [
        if (result.salePrice != null)
          'sale ₹${result.salePrice!.toStringAsFixed(2)}',
        if (result.mrp != null) 'MRP ₹${result.mrp!.toStringAsFixed(2)}',
      ].join(' · ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(details.isEmpty
            ? 'Shelf label read. Review before saving.'
            : 'Shelf label read: $details'),
      ));
    } on AiReceiptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.message),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Could not read this shelf label. Type the price manually.'),
      ));
    } finally {
      if (mounted) setState(() => scanningShelf = false);
    }
  }

  void _save() {
    if (name.text.trim().isEmpty) return;
    final existing = widget.existing;
    final exact = matched ?? widget.catalog.exactMatch(name.text);
    final expected = double.tryParse(price.text.trim()) ??
        exact?.latestUnitPrice ??
        existing?.expectedUnitPrice ??
        0;
    Navigator.pop(
      context,
      ShoppingItem(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        quantity: (double.tryParse(quantity.text) ?? 1).clamp(.01, 999),
        category: category,
        expectedUnitPrice: expected.clamp(0, double.infinity),
        bestUnitPrice: exact?.bestUnitPrice ??
            existing?.bestUnitPrice ??
            expected.clamp(0, double.infinity),
        bestStore: exact?.bestStore ?? existing?.bestStore ?? '',
        latestStore: exact?.latestStore ?? existing?.latestStore ?? '',
        note: note.text.trim(),
        remindAt: remindAt,
        completedAt: existing?.completedAt,
        sourceReceiptId: existing?.sourceReceiptId,
        mrp: shelfMrp ?? existing?.mrp,
        salePrice: shelfSalePrice ?? existing?.salePrice,
        createdAt: existing?.createdAt ?? DateTime.now(),
        checked: existing?.checked ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.existing == null ? t('addProduct') : t('editProduct')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: widget.existing == null,
                  onChanged: _nameChanged,
                  decoration: InputDecoration(
                    labelText: t('productOrType'),
                    hintText: t('forExampleTea'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Speak product name',
                      onPressed: listeningVoice ? null : _listenForProductName,
                      icon: listeningVoice
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mic_none_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: scanningShelf ? null : _scanShelfPrice,
                    icon: scanningShelf
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    label: Text(scanningShelf
                        ? t('readingShelfPrice')
                        : t('scanShelfPrice')),
                  ),
                ),
                if (shelfMrp != null || shelfSalePrice != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: CartSenseColors.surfaceMuted,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.sell_outlined, color: _green),
                      title: Text(t('shelfPriceCaptured')),
                      subtitle: Text([
                        if (shelfSalePrice != null)
                          'Sale ₹${shelfSalePrice!.toStringAsFixed(2)}',
                        if (shelfMrp != null)
                          'MRP ₹${shelfMrp!.toStringAsFixed(2)}',
                        if (shelfPackSize != null && shelfPackSize!.isNotEmpty)
                          shelfPackSize!,
                      ].join(' · ')),
                    ),
                  ),
                ],
                if (name.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: const Icon(Icons.auto_awesome, size: 17),
                      label: Text('Recognized: $category'),
                    ),
                  ),
                ],
                if (matches.isNotEmpty && matched == null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        'Matches from your bills',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  ...matches.map((product) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _selectProduct(product),
                        title: Text(product.name),
                        subtitle: Text(
                          '${product.category} · ₹${product.latestUnitPrice.toStringAsFixed(2)} at ${product.latestStore}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      )),
                ],
                if (matched != null)
                  Card(
                    color: CartSenseColors.success,
                    child: ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.verified_outlined, color: _green),
                      title: Text('Matched to ${matched!.name}'),
                      subtitle: Text(
                        'Latest ₹${matched!.latestUnitPrice.toStringAsFixed(2)} · best ₹${matched!.bestUnitPrice.toStringAsFixed(2)} at ${matched!.bestStore}',
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(labelText: t('quantity')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: t('unitPrice'),
                          prefixText: '₹ ',
                        ),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(category),
                  initialValue: category,
                  decoration: InputDecoration(labelText: t('category')),
                  items: GroceryCategory.values
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => category = value);
                  },
                ),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: t('noteOptional'),
                    hintText: t('brandSizePreference'),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(remindAt == null
                      ? t('addReminder')
                      : _reminderText(remindAt!)),
                  subtitle: remindAt == null
                      ? const Text('Optional Android notification at 9:00 AM')
                      : const Text('CartSense will notify you on this date'),
                  onTap: _pickReminder,
                  trailing: remindAt == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: 'Remove reminder',
                          onPressed: () => setState(() => remindAt = null),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: _save,
            child: Text(
                widget.existing == null ? t('addToList') : t('saveChanges')),
          ),
        ],
      );
}

class _ShoppingTripModeScreen extends StatefulWidget {
  const _ShoppingTripModeScreen({
    required this.items,
    required this.catalog,
    required this.onToggle,
    required this.onEdit,
  });

  final List<ShoppingItem> items;
  final ProductCatalog catalog;
  final Future<void> Function(ShoppingItem item, bool checked) onToggle;
  final void Function(ShoppingItem item) onEdit;

  @override
  State<_ShoppingTripModeScreen> createState() =>
      _ShoppingTripModeScreenState();
}

class _ShoppingTripModeScreenState extends State<_ShoppingTripModeScreen> {
  bool updating = false;
  final extraItems = <ShoppingItem>[];
  late double tripBudget;
  String languageCode = 'en';
  Future<OnlineCartComparison>? onlineCartComparison;

  List<ShoppingItem> get stillToBuy =>
      widget.items.where((item) => !item.checked).toList();
  List<ShoppingItem> get inCart =>
      widget.items.where((item) => item.checked).toList();
  List<ShoppingItem> get inBasket => [...inCart, ...extraItems];
  double get progress =>
      widget.items.isEmpty ? 0 : inCart.length / widget.items.length;
  double get cartEstimate =>
      inCart.fold(0, (total, item) => total + item.estimatedTotal);
  double get extraEstimate =>
      extraItems.fold(0, (total, item) => total + item.estimatedTotal);
  double get expectedBill => cartEstimate + extraEstimate;
  int get unknownPriceCount =>
      inBasket.where((item) => item.expectedUnitPrice <= 0).length;
  double get budgetGap => expectedBill - tripBudget;

  @override
  void initState() {
    super.initState();
    final plannedTotal =
        widget.items.fold(0.0, (total, item) => total + item.estimatedTotal);
    tripBudget = plannedTotal > 0 ? plannedTotal : 1000;
    _loadLanguage();
    _refreshCartComparison();
  }

  Future<void> _loadLanguage() async {
    final language = await LanguageStore().load();
    if (mounted) setState(() => languageCode = language.code);
  }

  String t(String key) => appText(languageCode, key);

  Future<void> _toggle(ShoppingItem item, bool checked) async {
    setState(() => updating = true);
    await widget.onToggle(item, checked);
    if (mounted) {
      setState(() => updating = false);
      _refreshCartComparison();
    }
  }

  void _refreshCartComparison() {
    final basket = inBasket;
    if (basket.isEmpty) {
      setState(() => onlineCartComparison = null);
      return;
    }
    setState(() {
      onlineCartComparison = PriceIntelligenceApi().compareCart(
        basket,
        budget: tripBudget,
      );
    });
  }

  Future<void> _setTripBudget() async {
    final controller = TextEditingController(
      text: tripBudget > 0 ? tripBudget.toStringAsFixed(0) : '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('setTripBudget')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Maximum amount before counter',
            prefixText: '₹ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.trim()) ?? tripBudget,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value > 0) {
      setState(() => tripBudget = value);
      _refreshCartComparison();
    }
  }

  Future<void> _addExtraItem() async {
    final item = await showDialog<ShoppingItem>(
      context: context,
      builder: (context) => _ShoppingItemEditor(
        catalog: widget.catalog,
        initialName: '',
      ),
    );
    if (item == null) return;
    setState(() {
      item.checked = true;
      item.note = item.note.isEmpty
          ? 'Extra picked during trip.'
          : '${item.note} · Extra picked during trip.';
      extraItems.add(item);
    });
    _refreshCartComparison();
  }

  List<ShoppingItem> _removalSuggestions() {
    if (budgetGap <= 0) return const [];
    const protectedCategories = {
      'Dairy & chilled',
      'Pantry staples',
      'Cooking oils',
      'Baby care',
      'Sanitary care',
    };
    final candidates = [
      ...extraItems,
      ...inCart.where((item) => !protectedCategories.contains(item.category)),
    ]..sort((a, b) => b.estimatedTotal.compareTo(a.estimatedTotal));
    return candidates.take(4).toList();
  }

  void _removeSuggestion(ShoppingItem item) {
    if (extraItems.any((value) => value.id == item.id)) {
      setState(() => extraItems.removeWhere((value) => value.id == item.id));
      _refreshCartComparison();
    } else {
      _toggle(item, false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ivory,
        appBar: AppBar(
          title: Text(t('tripMode')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('exit')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
          children: [
            Card(
              color: _green,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_grocery_store_outlined,
                            color: _lime),
                        const SizedBox(width: 8),
                        Text(
                          t('inStoreChecklist'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(_lime),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${inCart.length}/${widget.items.length} in cart · ₹${cartEstimate.toStringAsFixed(2)} estimated',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: budgetGap > 0
                  ? CartSenseColors.warning
                  : CartSenseColors.success,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          budgetGap > 0
                              ? Icons.warning_amber_rounded
                              : Icons.verified_outlined,
                          color: _green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            budgetGap > 0
                                ? 'Before counter: ₹${budgetGap.toStringAsFixed(2)} over budget'
                                : 'Before counter: ₹${budgetGap.abs().toStringAsFixed(2)} inside budget',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      unknownPriceCount > 0
                          ? '$unknownPriceCount ${t('unknownPrices')}'
                          : t('expectedBillIncludes'),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar:
                              const Icon(Icons.account_balance_wallet_outlined),
                          label: Text(
                              'Trip budget ₹${tripBudget.toStringAsFixed(0)}'),
                          onPressed: _setTripBudget,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add_shopping_cart_outlined),
                          label: Text(t('addExtraItem')),
                          onPressed: _addExtraItem,
                        ),
                      ],
                    ),
                    if (_removalSuggestions().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        t('removeToReduce'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      ..._removalSuggestions().map((item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.remove_circle_outline),
                            title: Text(item.name),
                            subtitle: Text(
                              item.estimatedTotal > 0
                                  ? 'Saves about ₹${item.estimatedTotal.toStringAsFixed(2)}'
                                  : t('priceUnknown'),
                            ),
                            trailing: TextButton(
                              onPressed: () => _removeSuggestion(item),
                              child: Text(t('remove')),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _onlineCartComparisonCard(),
            const SizedBox(height: 16),
            if (extraItems.isNotEmpty) ...[
              _tripSectionTitle(
                Icons.add_circle_outline,
                t('extraPicked'),
                extraItems.length,
              ),
              ...extraItems.map(
                (item) => _TripItemCard(
                  item: item,
                  checked: true,
                  onToggle: () {
                    setState(() =>
                        extraItems.removeWhere((value) => value.id == item.id));
                    _refreshCartComparison();
                  },
                  onEdit: () {},
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (stillToBuy.isNotEmpty) ...[
              _tripSectionTitle(
                Icons.radio_button_unchecked,
                t('stillToBuy'),
                stillToBuy.length,
              ),
              ...stillToBuy.map(
                (item) => _TripItemCard(
                  item: item,
                  checked: false,
                  onToggle: updating ? null : () => _toggle(item, true),
                  onEdit: () => widget.onEdit(item),
                ),
              ),
            ] else
              Card(
                color: CartSenseColors.success,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child:
                            const Icon(Icons.done_all, color: _green, size: 30),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Everything is in your cart',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'After checkout, scan the bill to reconcile your trip.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            if (inCart.isNotEmpty) ...[
              const SizedBox(height: 18),
              _tripSectionTitle(
                  Icons.shopping_cart_checkout, t('inCart'), inCart.length),
              ...inCart.map(
                (item) => _TripItemCard(
                  item: item,
                  checked: true,
                  onToggle: updating ? null : () => _toggle(item, false),
                  onEdit: () => widget.onEdit(item),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: const BoxDecoration(
              color: CartSenseColors.surface,
              border: Border(top: BorderSide(color: CartSenseColors.outline)),
            ),
            child: FilledButton.icon(
              onPressed: widget.items.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Checkout done — scan bill'),
            ),
          ),
        ),
      );

  Widget _onlineCartComparisonCard() {
    final future = onlineCartComparison;
    if (future == null) {
      return Card(
        color: CartSenseColors.surfaceMuted,
        child: ListTile(
          leading: const Icon(Icons.storefront_outlined, color: _green),
          title: const Text(
            'Store-wise best price',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            'Tick items or add extras to compare known prices before checkout.',
          ),
          trailing: IconButton(
            onPressed: _refreshCartComparison,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }
    return FutureBuilder<OnlineCartComparison>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: CartSenseColors.surfaceMuted,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Checking known store prices...',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(),
                ],
              ),
            ),
          );
        }
        final comparison = snapshot.data;
        final stores = comparison?.storeOptions ?? const <StoreCartOption>[];
        if (snapshot.hasError || comparison == null || stores.isEmpty) {
          return Card(
            color: CartSenseColors.surfaceMuted,
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined, color: _green),
              title: const Text(
                'Store-wise best price',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'No shared store prices yet. CartSense improves as receipts and shelf prices sync.',
              ),
              trailing: IconButton(
                onPressed: _refreshCartComparison,
                icon: const Icon(Icons.refresh),
              ),
            ),
          );
        }
        return Card(
          color: CartSenseColors.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: _green),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Best known store options',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _refreshCartComparison,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...stores.take(3).map(
                      (store) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_offer_outlined),
                        title: Text(store.storeName),
                        subtitle: Text(
                          store.missingItems.isEmpty
                              ? '${store.knownItems} known prices'
                              : '${store.knownItems} known · ${store.missingItems.length} missing',
                        ),
                        trailing: Text(
                          '₹${store.total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                if (comparison.overBudgetBy > 0) ...[
                  const Divider(),
                  Text(
                    'Online estimate is ₹${comparison.overBudgetBy.toStringAsFixed(0)} over budget.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tripSectionTitle(IconData icon, String title, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: _green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Chip(label: Text('$count')),
          ],
        ),
      );
}

class _TripItemCard extends StatelessWidget {
  const _TripItemCard({
    required this.item,
    required this.checked,
    required this.onToggle,
    required this.onEdit,
  });

  final ShoppingItem item;
  final bool checked;
  final VoidCallback? onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
        color: checked ? CartSenseColors.success : CartSenseColors.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: checked ? _green : CartSenseColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    checked ? Icons.check : Icons.add_shopping_cart_outlined,
                    color: checked ? Colors.white : _green,
                    size: 29,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.quantity.g} × ${item.name}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          decoration:
                              checked ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.category}${item.expectedUnitPrice > 0 ? ' · about ₹${item.estimatedTotal.toStringAsFixed(2)}' : ''}',
                        style: const TextStyle(
                          color: CartSenseColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit product',
                  onPressed: onEdit,
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ),
        ),
      );
}

String _reminderText(DateTime date) =>
    'Reminder ${date.day}/${date.month}/${date.year} at 9:00 AM';

extension on double {
  String get g => this == roundToDouble()
      ? toStringAsFixed(0)
      : toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
}
