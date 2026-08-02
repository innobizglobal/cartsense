import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_catalog.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../models/shopping_item.dart';
import '../services/shopping_list_store.dart';
import '../services/shopping_reminder_service.dart';
import '../theme/cartsense_theme.dart';
import '../widgets/category_icon.dart';

const _green = CartSenseColors.primary;
const _lime = CartSenseColors.accent;
const _ivory = CartSenseColors.background;

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key, required this.receipts});

  final List<Receipt> receipts;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final store = ShoppingListStore();
  final queryController = TextEditingController();
  List<ShoppingItem> items = [];
  List<CatalogProduct> searchResults = [];
  bool loading = true;

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
              ? '${edited.name} added as ${edited.category}.'
              : '${edited.name} updated.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
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

  Map<String, List<ShoppingItem>> get _storePlan {
    final plan = <String, List<ShoppingItem>>{};
    for (final item in activeItems) {
      final storeName =
          item.bestStore.isEmpty ? 'Price needed' : item.bestStore;
      plan.putIfAbsent(storeName, () => []).add(item);
    }
    return plan;
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

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        title: const Text('Shopping list'),
        actions: [
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
                              const Text('Estimated basket',
                                  style: TextStyle(color: Colors.white70)),
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
                            ],
                          ),
                        ),
                        if (possibleSaving > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Possible saving',
                                  style: TextStyle(color: Colors.white70)),
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
                    labelText: 'Add a product',
                    hintText: 'Tea, milk, oil or a brand',
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
                              ? const Icon(Icons.add_circle_outline)
                              : Text(
                                  'Best ₹${product.bestUnitPrice.toStringAsFixed(2)}\n${product.bestStore}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 12),
                                ),
                        ),
                      )),
                ],
                const SizedBox(height: 20),
                _sectionTitle(Icons.checklist, 'Shopping list'),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Search for a product above. CartSense will recognize its category and show matching products from your bills.',
                      ),
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
                            onPressed: () => _openEditor(frequent: suggestion),
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
                            'Scan the checkout bill to match purchases, keep missing products, and find unplanned spending.',
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

  String _itemSubtitle(ShoppingItem item) {
    final parts = <String>[item.category];
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
    matches = widget.catalog.search(name.text, limit: 4);
  }

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
        createdAt: existing?.createdAt ?? DateTime.now(),
        checked: existing?.checked ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Add product' : 'Edit product'),
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
                  decoration: const InputDecoration(
                    labelText: 'Product or product type',
                    hintText: 'For example Tea',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
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
                        decoration:
                            const InputDecoration(labelText: 'Quantity'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Unit price',
                          prefixText: '₹ ',
                        ),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(category),
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
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
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'Brand, size or preference',
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(remindAt == null
                      ? 'Add reminder'
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _save,
            child:
                Text(widget.existing == null ? 'Add to list' : 'Save changes'),
          ),
        ],
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
