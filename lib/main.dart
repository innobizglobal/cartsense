import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'demo_receipt.dart';
import 'models/receipt.dart';
import 'models/shopping_item.dart';
import 'models/shopping_trip.dart';
import 'models/spending_insights.dart';
import 'screens/insights_screen.dart';
import 'screens/shopping_list_screen.dart';
import 'screens/shopping_reconciliation_screen.dart';
import 'services/receipt_export.dart';
import 'services/ai_receipt_service.dart';
import 'services/receipt_parser.dart';
import 'services/receipt_store.dart';
import 'services/shopping_list_store.dart';
import 'theme/cartsense_theme.dart';
import 'widgets/category_icon.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: CartSenseColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const CartSenseApp());
}

const green = CartSenseColors.primary;
const lime = CartSenseColors.accent;
const ivory = CartSenseColors.background;

class CartSenseApp extends StatelessWidget {
  const CartSenseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CartSense',
        theme: buildCartSenseTheme(),
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
  final aiService = AiReceiptService();
  final store = ReceiptStore();
  final searchController = TextEditingController();
  List<Receipt> history = [];
  int activeShoppingCount = 0;
  bool busy = false;
  bool usingAi = false;
  String query = '';

  SpendingInsights get monthlyInsights => SpendingInsights.forMonth(history);

  List<Receipt> get filteredHistory {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return history;
    return history
        .where((receipt) =>
            receipt.store.toLowerCase().contains(needle) ||
            receipt.items.any((item) =>
                item.name.toLowerCase().contains(needle) ||
                item.category.toLowerCase().contains(needle)))
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
    final shoppingItems = await ShoppingListStore().load();
    if (mounted) {
      setState(() {
        history = items;
        activeShoppingCount =
            shoppingItems.where((item) => !item.checked).length;
      });
    }
  }

  Future<bool> _confirmAiConsent() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('cartsense_ai_consent') == true) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use AI Enhanced Scan?'),
        content: const Text(
          'Your receipt photo will be sent securely to the CartSense service and OpenAI for recognition. '
          'CartSense processes the image in memory and does not save it on the service. '
          'You can use the private on-device reader instead at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await preferences.setBool('cartsense_ai_consent', true);
      return true;
    }
    return false;
  }

  Future<void> _capture(ImageSource source, {bool aiEnhanced = false}) async {
    if (aiEnhanced && !aiService.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'AI Enhanced Scan is not configured in this build. Private scanning is available.',
          ),
        ));
      }
      return;
    }
    if (aiEnhanced && !await _confirmAiConsent()) return;
    final image = await picker.pickImage(
      source: source,
      imageQuality: aiEnhanced ? 88 : 92,
      maxWidth: aiEnhanced ? 2200 : 2400,
    );
    if (image == null || !mounted) return;
    setState(() {
      busy = true;
      usingAi = aiEnhanced;
    });
    try {
      final file = File(image.path);
      final receipt =
          aiEnhanced ? await aiService.parse(file) : await parser.parse(file);
      if (mounted) await _open(receipt);
    } catch (error) {
      if (mounted) {
        final message = error is AiReceiptException
            ? error.message
            : error is FormatException
                ? error.message.toString()
                : error is PlatformException
                    ? 'On-device reader error ${error.code}: ${error.message ?? 'unknown error'}'
                    : 'The bill could not be read. Please try another photo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          usingAi = false;
        });
      }
    }
  }

  Future<void> _showPrivateScanOptions() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Private on-device reader',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('The receipt photo stays on this phone.'),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await _capture(source);
  }

  Future<void> _showCheckoutScanOptions() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Scan your checkout bill',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                'CartSense will compare this bill with your saved shopping list.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('AI scan with camera'),
              onTap: () => Navigator.pop(context, 'ai_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('AI scan from gallery'),
              onTap: () => Navigator.pop(context, 'ai_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Private on-device scan'),
              onTap: () => Navigator.pop(context, 'private'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;
    if (selection == 'ai_camera') {
      await _capture(ImageSource.camera, aiEnhanced: true);
    } else if (selection == 'ai_gallery') {
      await _capture(ImageSource.gallery, aiEnhanced: true);
    } else {
      await _showPrivateScanOptions();
    }
  }

  Future<void> _open(Receipt receipt) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(receipt: receipt),
    ));
    await _refresh();
  }

  Future<void> _openInsights() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InsightsScreen(receipts: history),
    ));
  }

  Future<void> _openShoppingAssistant() async {
    final scanNow = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShoppingListScreen(receipts: history),
    ));
    await _refresh();
    if (scanNow == true && mounted) await _showCheckoutScanOptions();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: const Row(
            children: [
              _BrandMark(),
              SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CartSense'),
                  Text(
                    'Smart grocery companion',
                    style: TextStyle(
                      color: CartSenseColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'private') {
                  _showPrivateScanOptions();
                } else if (value == 'demo') {
                  _open(createDemoReceipt());
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'private',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline),
                    title: Text('Private scan'),
                  ),
                ),
                PopupMenuItem(
                  value: 'demo',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.science_outlined),
                    title: Text('Open sample receipt'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: busy
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text(
                        usingAi
                            ? 'AI is carefully reading your bill...'
                            : 'Reading your bill privately on this device...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        usingAi
                            ? 'Checking product rows, taxes, item count and the printed total.'
                            : 'This can take a few seconds. No receipt data is uploaded.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [CartSenseColors.primaryDark, green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              _HeroIcon(),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Scan a grocery receipt',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        height: 1.1,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Save products, prices and spending automatically.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: lime,
                                  foregroundColor: green,
                                  padding: const EdgeInsets.all(16)),
                              onPressed: _showCheckoutScanOptions,
                              icon: const Icon(Icons.document_scanner),
                              label: const Text('Scan receipt',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shield_outlined,
                                  size: 16, color: Colors.white70),
                              SizedBox(width: 6),
                              Text(
                                'You choose AI or private on-device scan',
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
                    const SizedBox(height: 22),
                    const _HomeSectionTitle('Your shortcuts'),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeFeatureButton(
                            icon: Icons.savings_outlined,
                            title: 'Insights',
                            subtitle: 'Budget and price trends',
                            onTap: _openInsights,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HomeFeatureButton(
                            icon: Icons.shopping_cart_outlined,
                            title: 'Shopping list',
                            subtitle: activeShoppingCount == 0
                                ? 'Plan your next trip'
                                : '$activeShoppingCount products to buy',
                            onTap: _openShoppingAssistant,
                          ),
                        ),
                      ],
                    ),
                    if (monthlyInsights.billCount > 0) ...[
                      const SizedBox(height: 18),
                      Card(
                        color: CartSenseColors.surfaceMuted,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.insights_outlined, color: green),
                                  SizedBox(width: 8),
                                  Text(
                                    'This month',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '₹${monthlyInsights.total.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: green,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              Text(
                                '${monthlyInsights.billCount} saved ${monthlyInsights.billCount == 1 ? 'bill' : 'bills'}',
                              ),
                              if (monthlyInsights.topCategory != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Top category: ${monthlyInsights.topCategory} · ₹${monthlyInsights.topCategoryTotal.toStringAsFixed(2)}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _HomeSectionTitle(
                      'Recent receipts',
                      trailing:
                          history.isEmpty ? null : '${history.length} saved',
                    ),
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
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (history.isEmpty)
                      const _HomeEmptyState()
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
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                7,
                                10,
                                7,
                              ),
                              onTap: () => _open(receipt),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: CartSenseColors.success,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: green,
                                ),
                              ),
                              title: Text(
                                receipt.store,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${receipt.items.length} products · ${_shortDate(receipt.purchasedAt)}${receipt.shoppingTrip == null ? '' : ' · reconciled'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '₹${receipt.calculatedTotal.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: CartSenseColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          )),
                  ],
                ),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (index) {
            if (index == 1) {
              _showCheckoutScanOptions();
            } else if (index == 2) {
              _openShoppingAssistant();
            } else if (index == 3) {
              _openInsights();
            }
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              selectedIcon: Icon(Icons.document_scanner),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeShoppingCount > 0,
                label: Text('$activeShoppingCount'),
                child: const Icon(Icons.shopping_basket_outlined),
              ),
              selectedIcon: const Icon(Icons.shopping_basket),
              label: 'List',
            ),
            const NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Insights',
            ),
          ],
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.shopping_bag_outlined,
            color: Colors.white, size: 21),
      );
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.receipt_long_outlined,
            color: Colors.white, size: 28),
      );
}

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                color: CartSenseColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      );
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: CartSenseColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: green, size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'No receipts yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              const Text(
                'Scan your first grocery receipt to start tracking prices and spending.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CartSenseColors.textMuted),
              ),
            ],
          ),
        ),
      );
}

class _HomeFeatureButton extends StatelessWidget {
  const _HomeFeatureButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CartSenseColors.success,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: green),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CartSenseColors.textMuted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.receipt});
  final Receipt receipt;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Receipt receipt = widget.receipt;
  bool saving = false;

  bool get _hasReceiptImage {
    final path = receipt.imagePath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  Future<void> _showOriginalReceipt() async {
    final path = receipt.imagePath;
    if (path == null || !File(path).existsSync()) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptImageScreen(imagePath: path),
      ),
    );
  }

  Future<void> _deleteReceipt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text(
          '${receipt.store} and its saved image will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete receipt'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ReceiptStore().delete(receipt.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reviewNextItem() async {
    final index = receipt.items.indexWhere((item) => item.needsReview);
    if (index >= 0) await _editItem(index);
  }

  Future<void> _addToShoppingList(ReceiptItem item) async {
    final unitPrice = item.unitPrice > 0
        ? item.unitPrice
        : item.quantity > 0
            ? item.total / item.quantity
            : item.total;
    await ShoppingListStore().add(ShoppingItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: item.name,
      quantity: 1,
      category: item.category,
      expectedUnitPrice: unitPrice,
      bestUnitPrice: unitPrice,
      bestStore: receipt.store,
      latestStore: receipt.store,
      sourceReceiptId: receipt.id,
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} added to your shopping list.')),
    );
  }

  Future<void> _saveAndReconcile() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await ReceiptStore().save(receipt);
      if (!mounted) return;
      if (receipt.shoppingTrip != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bill changes saved on this device.'),
        ));
        return;
      }
      final shoppingItems = await ShoppingListStore().load();
      final plannedItems = shoppingItems
          .where((item) => item.reconciledReceiptId == null)
          .toList();
      if (!mounted) return;
      if (plannedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Receipt saved. Add products to your shopping list to plan the next trip.',
          ),
        ));
        return;
      }
      final result = await Navigator.of(context).push<ShoppingTripResult>(
        MaterialPageRoute(
          builder: (_) => ShoppingReconciliationScreen(
            receipt: receipt,
            plannedItems: plannedItems,
          ),
        ),
      );
      if (result == null || !mounted) return;
      setState(() => receipt.shoppingTrip = result);
      await ReceiptStore().save(receipt);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Trip finished: ${result.matches.length} bought, ${result.missing.length} still on your list.',
        ),
      ));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

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
    var category = item.category;
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
        item.category = category;
        item.parsedLineTotal = null;
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
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Receipt details'),
              Text(
                receipt.store,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CartSenseColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Receipt options',
              onSelected: (value) {
                if (value == 'image') {
                  _showOriginalReceipt();
                } else if (value == 'export') {
                  ReceiptExport().shareCsv(receipt);
                } else if (value == 'delete') {
                  _deleteReceipt();
                }
              },
              itemBuilder: (context) => [
                if (_hasReceiptImage)
                  const PopupMenuItem(
                    value: 'image',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.image_outlined),
                      title: Text('View receipt image'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.ios_share_outlined),
                    title: Text('Export receipt'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete receipt'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: receipt.confidentlyReconciled
                    ? CartSenseColors.success
                    : CartSenseColors.warning,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                Icon(
                    receipt.confidentlyReconciled
                        ? Icons.verified_outlined
                        : Icons.warning_amber_rounded,
                    color: green),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        receipt.confidentlyReconciled
                            ? 'Receipt looks good'
                            : receipt.reconciled
                                ? 'Total matches · review highlighted products'
                                : 'Totals differ by ₹${receipt.difference.abs().toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
            const SizedBox(height: 14),
            if (receipt.shoppingTrip case final trip?) ...[
              _tripSummary(trip),
              const SizedBox(height: 8),
            ],
            if (receipt.reviewItemCount > 0) ...[
              Card(
                color: CartSenseColors.warning,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check_outlined, color: green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${receipt.reviewItemCount} ${receipt.reviewItemCount == 1 ? 'item needs' : 'items need'} your review',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _reviewNextItem,
                        child: const Text('Review next'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            OutlinedButton.icon(
              onPressed: _editDetails,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Edit receipt details'),
            ),
            const SizedBox(height: 6),
            if (receipt.isAiEnhanced) ...[
              Card(
                color: CartSenseColors.surfaceMuted,
                child: ExpansionTile(
                  leading: const Icon(Icons.auto_awesome, color: green),
                  title: const Text(
                    'Scan quality',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${(receipt.overallConfidence * 100).round()}% confidence${receipt.warnings.isEmpty ? '' : ' · ${receipt.warnings.length} notes'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (receipt.printedItemCount != null)
                          Chip(
                            label: Text(
                              '${receipt.items.length}/${receipt.printedItemCount} products',
                            ),
                          ),
                        if (receipt.printedQuantityTotal != null)
                          Chip(
                            label: Text(
                              'Quantity ${receipt.printedQuantityTotal!.g}',
                            ),
                          ),
                      ],
                    ),
                    if (receipt.warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...receipt.warnings.take(4).map(
                            (warning) => Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline,
                                      size: 17, color: green),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(warning)),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            _HomeSectionTitle(
              'Products',
              trailing: '${receipt.items.length}',
            ),
            const SizedBox(height: 7),
            ...List.generate(receipt.items.length, (index) {
              final item = receipt.items[index];
              return Card(
                color:
                    item.needsReview ? CartSenseColors.warning : Colors.white,
                child: ListTile(
                  onTap: () => _editItem(index),
                  leading: CategoryAvatar(category: item.category),
                  title: Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${item.quantity.g} × ₹${item.unitPrice.toStringAsFixed(2)}  •  Discount ₹${item.discount.toStringAsFixed(2)}\n${item.category}${item.needsReview ? '  •  REVIEW' : ''}'),
                  isThreeLine: true,
                  trailing: SizedBox(
                    width: 104,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            '₹${item.total.toStringAsFixed(2)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Add to shopping list',
                          onPressed: () => _addToShoppingList(item),
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                        ),
                      ],
                    ),
                  ),
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
            _total('Product subtotal', receipt.itemSubtotal),
            if (receipt.taxTotal > 0) _total('Tax', receipt.taxTotal),
            if (receipt.otherCharges > 0)
              _total('Other charges', receipt.otherCharges),
            if (receipt.billDiscount > 0)
              _total('Bill discount', -receipt.billDiscount),
            _total('Printed bill total', receipt.printedTotal),
            _total('Calculated total', receipt.calculatedTotal, strong: true),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: saving ? null : _saveAndReconcile,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(receipt.shoppingTrip == null
                      ? Icons.sync_alt
                      : Icons.save_outlined),
              label: Text(saving
                  ? 'Saving…'
                  : receipt.shoppingTrip == null
                      ? 'Save bill & reconcile shopping list'
                      : 'Save bill changes'),
            ),
          ],
        ),
      );

  Widget _tripSummary(ShoppingTripResult trip) => Card(
        color: CartSenseColors.success,
        child: ExpansionTile(
          leading: const Icon(Icons.done_all, color: green),
          title: const Text(
            'Shopping trip reconciled',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${trip.matches.length} bought · ${trip.missing.length} still needed · ${trip.unplanned.length} unplanned\nPlanned ₹${trip.plannedEstimate.toStringAsFixed(2)} · Bill ₹${trip.billTotal.toStringAsFixed(2)}',
          ),
          children: [
            if (trip.matches.isNotEmpty)
              ...trip.matches.map((item) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text('${item.plannedName} → ${item.purchasedName}'),
                    trailing: Text('₹${item.actualTotal.toStringAsFixed(2)}'),
                  )),
            if (trip.missing.isNotEmpty)
              ...trip.missing.map((item) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.pending_outlined),
                    title: Text('${item.name} remains on the list'),
                  )),
            if (trip.unplanned.isNotEmpty)
              ...trip.unplanned.map((item) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text('${item.name} was unplanned'),
                    trailing: Text('₹${item.actualTotal.toStringAsFixed(2)}'),
                  )),
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

class ReceiptImageScreen extends StatelessWidget {
  const ReceiptImageScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Original receipt'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              boundaryMargin: const EdgeInsets.all(80),
              child: Image.file(
                File(imagePath),
                semanticLabel: 'Original grocery receipt',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'The original receipt image is no longer available.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

extension CompactNumber on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
