import 'package:flutter/material.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../models/shopping_item.dart';
import '../services/shopping_list_store.dart';

const _green = Color(0xFF174C3C);
const _lime = Color(0xFFB8E05A);
const _ivory = Color(0xFFFFFBF2);

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key, required this.receipts});

  final List<Receipt> receipts;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final store = ShoppingListStore();
  List<ShoppingItem> items = [];
  bool loading = true;

  SavingsIntelligence get intelligence =>
      SavingsIntelligence.fromReceipts(widget.receipts);

  double get estimatedTotal =>
      items.fold(0, (total, item) => total + item.estimatedTotal);

  double get possibleSaving =>
      items.fold(0, (total, item) => total + item.possibleSaving);

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _persist() => store.saveAll(items);

  ProductPriceInsight? _priceFor(String name) {
    final key = normalizedProductName(name);
    for (final insight in intelligence.priceInsights) {
      if (normalizedProductName(insight.name) == key) return insight;
    }
    return null;
  }

  Future<void> _addItem({FrequentProduct? suggestion}) async {
    final name = TextEditingController(text: suggestion?.name ?? '');
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController(
      text: suggestion == null ? '' : suggestion.latestPrice.toStringAsFixed(2),
    );
    var category = suggestion?.category ?? GroceryCategory.other;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add shopping item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: suggestion == null,
                decoration: const InputDecoration(labelText: 'Product'),
              ),
              TextField(
                controller: quantity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              TextField(
                controller: price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Expected unit price (optional)',
                  prefixText: '₹ ',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: GroceryCategory.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) category = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (save == true && name.text.trim().isNotEmpty) {
      final priceInsight = _priceFor(name.text);
      final expected = double.tryParse(price.text) ??
          priceInsight?.latestPrice ??
          suggestion?.latestPrice ??
          0;
      final best = priceInsight?.bestPrice ?? suggestion?.bestPrice ?? expected;
      final bestStore = priceInsight?.bestStore ?? suggestion?.bestStore ?? '';
      final item = ShoppingItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        quantity: (double.tryParse(quantity.text) ?? 1).clamp(.01, 999),
        category: category,
        expectedUnitPrice: expected.clamp(0, double.infinity),
        bestUnitPrice: best.clamp(0, double.infinity),
        bestStore: bestStore,
        createdAt: DateTime.now(),
      );
      await store.add(item);
      await _load();
    }
    name.dispose();
    quantity.dispose();
    price.dispose();
  }

  Future<void> _removeChecked() async {
    setState(() => items.removeWhere((item) => item.checked));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = intelligence.frequentProducts
        .where((item) =>
            item.isDueAt(DateTime.now()) &&
            !items.any((current) =>
                normalizedProductName(current.name) ==
                normalizedProductName(item.name)))
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        title: const Text('Shopping assistant'),
        actions: [
          if (items.any((item) => item.checked))
            IconButton(
              tooltip: 'Remove checked items',
              onPressed: _removeChecked,
              icon: const Icon(Icons.cleaning_services_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        backgroundColor: _lime,
        foregroundColor: _green,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
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
                              const Text(
                                'Estimated basket',
                                style: TextStyle(color: Colors.white70),
                              ),
                              Text(
                                '₹${estimatedTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (possibleSaving > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Possible saving',
                                style: TextStyle(color: Colors.white70),
                              ),
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
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'You may need these again',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  ...suggestions.map((item) => Card(
                        color: const Color(0xFFE8F4D7),
                        child: ListTile(
                          leading: const Icon(Icons.history, color: _green),
                          title: Text(item.name),
                          subtitle: Text(
                            'Bought ${item.purchaseCount} times · about ₹${item.latestPrice.toStringAsFixed(2)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Add to list',
                            onPressed: () => _addItem(suggestion: item),
                            icon: const Icon(Icons.add_circle, color: _green),
                          ),
                        ),
                      )),
                ],
                const SizedBox(height: 20),
                Text(
                  'My list',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Your list is empty. Add an item or save more bills to get repeat-purchase suggestions.',
                      ),
                    ),
                  )
                else
                  ...items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Card(
                      child: CheckboxListTile(
                        value: item.checked,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) async {
                          setState(() => item.checked = value == true);
                          await _persist();
                        },
                        title: Text(
                          '${item.quantity.g} × ${item.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: item.checked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          item.bestStore.isNotEmpty && item.possibleSaving > 0
                              ? 'Estimate ₹${item.estimatedTotal.toStringAsFixed(2)} · best price at ${item.bestStore}'
                              : item.expectedUnitPrice > 0
                                  ? 'Estimate ₹${item.estimatedTotal.toStringAsFixed(2)} · ${item.category}'
                                  : item.category,
                        ),
                        secondary: IconButton(
                          tooltip: 'Remove item',
                          onPressed: () async {
                            setState(() => items.removeAt(index));
                            await _persist();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble()
      ? toStringAsFixed(0)
      : toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
}
