import 'dart:io';
import 'package:flutter/material.dart';
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
  List<Receipt> history = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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
    if (!parser.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Bill captured. Live AI reading will be connected in the next build. You can test the full workflow with Demo bill.'),
      ));
      return;
    }
    setState(() => busy = true);
    try {
      final receipt = await parser.parse(File(image.path));
      if (mounted) await _open(receipt);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
            ? const Center(child: CircularProgressIndicator())
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
                              'Photograph your receipt, check each item and keep a clean spending history.',
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
                    if (history.isEmpty)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                  'No saved bills yet. Scan one or open the demo.')))
                    else
                      ...history.map((receipt) => Card(
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
                              trailing: Text(
                                  '₹${receipt.calculatedTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
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

  Future<void> _editItem(int index) async {
    final item = receipt.items[index];
    final name = TextEditingController(text: item.name);
    final quantity = TextEditingController(text: item.quantity.toString());
    final price =
        TextEditingController(text: item.unitPrice.toStringAsFixed(2));
    final discount =
        TextEditingController(text: item.discount.toStringAsFixed(2));
    final save = await showDialog<bool>(
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (save == true) {
      setState(() {
        item.name = name.text.trim();
        item.quantity = double.tryParse(quantity.text) ?? item.quantity;
        item.unitPrice = double.tryParse(price.text) ?? item.unitPrice;
        item.discount = double.tryParse(discount.text) ?? item.discount;
        item.confidence = 1;
      });
    }
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
