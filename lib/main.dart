import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'demo_receipt.dart';
import 'models/receipt.dart';
import 'services/receipt_export.dart';
import 'services/receipt_parser.dart';
import 'services/receipt_store.dart';

void main() => runApp(const CartSenseApp());

const green = Color(0xFF174C3C);
const lime = Color(0xFFB8E05A);
const ivory = Color(0xFFFFFBF2);

class CartSenseApp extends StatelessWidget {
  const CartSenseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CartSense',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: green),
          scaffoldBackgroundColor: ivory,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: ivory,
            foregroundColor: green,
            elevation: 0,
          ),
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final picker = ImagePicker();
  final parser = ReceiptParser();
  final store = ReceiptStore();
  final searchController = TextEditingController();
  List<Receipt> history = [];
  bool busy = false;
  String query = '';

  List<Receipt> get filteredHistory {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return history;
    return history
        .where((receipt) =>
            receipt.store.toLowerCase().contains(needle) ||
            receipt.items
                .any((item) => item.name.toLowerCase().contains(needle)))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final items = await store.load();
    if (mounted) setState(() => history = items);
  }

  Future<void> _capture(ImageSource source) async {
    final image = await picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null || !mounted) return;
    setState(() => busy = true);
    try {
      final receipt = await parser.parse(File(image.path));
      if (mounted) await _open(receipt);
    } catch (error) {
      if (mounted) {
        final message = error is FormatException
            ? error.message.toString()
            : error is PlatformException
                ? 'On-device reader error ${error.code}: ${error.message ?? 'unknown error'}'
                : 'The bill could not be read. Please try another photo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _open(Receipt receipt) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(receipt: receipt),
    ));
    await _refresh();
  }

  Future<void> _deleteReceipt(Receipt receipt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved bill?'),
        content: Text(
          '${receipt.store} will be removed from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.delete(receipt.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('CartSense',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Chip(label: Text('PRIVATE ON DEVICE')),
            ),
          ],
        ),
        body: busy
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text(
                        'Reading your bill privately on this device...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'This can take a few seconds. No receipt data is uploaded.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: green,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Turn every grocery bill\ninto useful savings.',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Text(
                              'Photograph your receipt, read it privately on this device and keep a clean spending history.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .82),
                                  fontSize: 16)),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: lime,
                                  foregroundColor: green,
                                  padding: const EdgeInsets.all(17)),
                              onPressed: () => _capture(ImageSource.camera),
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('Scan grocery bill',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                  padding: const EdgeInsets.all(16)),
                              onPressed: () => _capture(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Choose from gallery'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => _open(createDemoReceipt()),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Try a complete demo bill'),
                    ),
                    const SizedBox(height: 28),
                    Text('Recent bills',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    if (history.isNotEmpty) ...[
                      TextField(
                        controller: searchController,
                        onChanged: (value) => setState(() => query = value),
                        decoration: InputDecoration(
                          hintText: 'Search stores or grocery items',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    searchController.clear();
                                    setState(() => query = '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (history.isEmpty)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                  'No saved bills yet. Scan one or open the demo.')))
                    else if (filteredHistory.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No saved bills match your search.'),
                        ),
                      )
                    else
                      ...filteredHistory.map((receipt) => Card(
                            child: ListTile(
                              onTap: () => _open(receipt),
                              leading: const CircleAvatar(
                                  backgroundColor: lime,
                                  child:
                                      Icon(Icons.receipt_long, color: green)),
                              title: Text(receipt.store,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${receipt.items.length} items • ${receipt.purchasedAt.day}/${receipt.purchasedAt.month}/${receipt.purchasedAt.year}'),
                              trailing: SizedBox(
                                width: 116,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '₹${receipt.calculatedTotal.toStringAsFixed(2)}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete bill',
                                      onPressed: () => _deleteReceipt(receipt),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )),
                  ],
                ),
              ),
      );
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.receipt});
  final Receipt receipt;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Receipt receipt = widget.receipt;

  Future<void> _editDetails() async {
    final store = TextEditingController(text: receipt.store);
    final date = TextEditingController(
      text:
          '${receipt.purchasedAt.day}/${receipt.purchasedAt.month}/${receipt.purchasedAt.year}',
    );
    final total =
        TextEditingController(text: receipt.printedTotal.toStringAsFixed(2));
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit bill details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: store,
                decoration: const InputDecoration(labelText: 'Store name'),
              ),
              TextField(
                controller: date,
                keyboardType: TextInputType.datetime,
                decoration:
                    const InputDecoration(labelText: 'Date (day/month/year)'),
              ),
              TextField(
                controller: total,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Printed bill total'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (shouldSave == true) {
      final dateParts = date.text.trim().split(RegExp(r'[/.-]'));
      DateTime? parsedDate;
      if (dateParts.length == 3) {
        final day = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final year = int.tryParse(dateParts[2]);
        if (day != null && month != null && year != null) {
          final candidate = DateTime(year, month, day);
          if (candidate.day == day &&
              candidate.month == month &&
              candidate.year == year) {
            parsedDate = candidate;
          }
        }
      }
      setState(() {
        if (store.text.trim().isNotEmpty) receipt.store = store.text.trim();
        receipt.printedTotal =
            double.tryParse(total.text) ?? receipt.printedTotal;
        receipt.purchasedAt = parsedDate ?? receipt.purchasedAt;
      });
    }
    store.dispose();
    date.dispose();
    total.dispose();
  }

  Future<void> _editItem(int index) async {
    final item = receipt.items[index];
    final name = TextEditingController(text: item.name);
    final quantity = TextEditingController(text: item.quantity.toString());
    final price =
        TextEditingController(text: item.unitPrice.toStringAsFixed(2));
    final discount =
        TextEditingController(text: item.discount.toStringAsFixed(2));
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit item'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Product name')),
            TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity')),
            TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Unit price')),
            TextField(
                controller: discount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Discount')),
          ]),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Delete')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    if (action == 'delete') {
      setState(() => receipt.items.removeAt(index));
    } else if (action == 'save') {
      setState(() {
        item.name = name.text.trim();
        item.quantity = double.tryParse(quantity.text) ?? item.quantity;
        item.unitPrice = double.tryParse(price.text) ?? item.unitPrice;
        item.discount = double.tryParse(discount.text) ?? item.discount;
        item.confidence = 1;
      });
    }
    name.dispose();
    quantity.dispose();
    price.dispose();
    discount.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(receipt.store)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: receipt.reconciled
                    ? const Color(0xFFE8F4D7)
                    : const Color(0xFFFFE8DA),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                Icon(
                    receipt.reconciled
                        ? Icons.verified_outlined
                        : Icons.warning_amber_rounded,
                    color: green),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        receipt.reconciled
                            ? 'Bill total matches'
                            : 'Please review: difference ₹${receipt.difference.abs().toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _editDetails,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Edit store, date or printed total'),
            ),
            const SizedBox(height: 6),
            ...List.generate(receipt.items.length, (index) {
              final item = receipt.items[index];
              return Card(
                color:
                    item.needsReview ? const Color(0xFFFFF3CD) : Colors.white,
                child: ListTile(
                  onTap: () => _editItem(index),
                  title: Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${item.quantity.g} × ₹${item.unitPrice.toStringAsFixed(2)}  •  Discount ₹${item.discount.toStringAsFixed(2)}${item.needsReview ? '  •  REVIEW' : ''}'),
                  trailing: Text('₹${item.total.toStringAsFixed(2)}'),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => receipt.items.add(ReceiptItem(
                  name: 'New item',
                  quantity: 1,
                  unitPrice: 0,
                  discount: 0,
                  confidence: 1))),
              icon: const Icon(Icons.add),
              label: const Text('Add missing item'),
            ),
            const Divider(height: 28),
            _total('Printed bill total', receipt.printedTotal),
            _total('Calculated total', receipt.calculatedTotal, strong: true),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                await ReceiptStore().save(receipt);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Bill saved on this device.'),
                ));
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save bill'),
            ),
            OutlinedButton.icon(
              onPressed: () => ReceiptExport().shareCsv(receipt),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Export for Excel'),
            ),
          ],
        ),
      );

  Widget _total(String label, double amount, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: strong ? 21 : 16, fontWeight: FontWeight.w800)),
        ]),
      );
}

extension CompactNumber on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
