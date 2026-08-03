import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_catalog.dart';
import '../models/receipt.dart';
import '../models/shopping_item.dart';
import '../services/shopping_list_store.dart';
import '../theme/cartsense_theme.dart';
import '../widgets/app_footer_nav.dart';
import '../widgets/category_icon.dart';

const _green = CartSenseColors.primary;
const _lime = CartSenseColors.accent;
const _ivory = CartSenseColors.background;

class ProductMasterScreen extends StatefulWidget {
  const ProductMasterScreen({
    super.key,
    required this.receipts,
    this.activeShoppingCount = 0,
    this.onScan,
    this.onOpenShoppingList,
    this.onOpenInsights,
  });

  final List<Receipt> receipts;
  final int activeShoppingCount;
  final VoidCallback? onScan;
  final VoidCallback? onOpenShoppingList;
  final VoidCallback? onOpenInsights;

  @override
  State<ProductMasterScreen> createState() => _ProductMasterScreenState();
}

class _ProductMasterScreenState extends State<ProductMasterScreen> {
  static const _favoritesKey = 'cartsense_favorite_products_v1';

  late final ProductCatalog catalog = ProductCatalog.fromReceipts(
    widget.receipts,
  );
  final searchController = TextEditingController();
  Set<String> favorites = {};
  String query = '';
  bool favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      favorites = (preferences.getStringList(_favoritesKey) ?? []).toSet();
    });
  }

  Future<void> _toggleFavorite(CatalogProduct product) async {
    setState(() {
      if (!favorites.remove(product.key)) favorites.add(product.key);
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_favoritesKey, favorites.toList()..sort());
  }

  List<CatalogProduct> get products {
    final source = query.trim().isEmpty
        ? catalog.products
        : catalog.search(query, limit: catalog.products.length);
    final filtered = favoritesOnly
        ? source.where((product) => favorites.contains(product.key)).toList()
        : source.toList();
    filtered.sort((a, b) {
      final aFav = favorites.contains(a.key);
      final bFav = favorites.contains(b.key);
      if (aFav != bFav) return aFav ? -1 : 1;
      final count = b.purchaseCount.compareTo(a.purchaseCount);
      if (count != 0) return count;
      return b.lastPurchased.compareTo(a.lastPurchased);
    });
    return filtered;
  }

  Future<void> _addToShoppingList(CatalogProduct product) async {
    await ShoppingListStore().add(ShoppingItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: product.name,
      quantity: 1,
      category: product.category,
      expectedUnitPrice: product.latestUnitPrice,
      bestUnitPrice: product.bestUnitPrice,
      bestStore: product.bestStore,
      latestStore: product.latestStore,
      note: favorites.contains(product.key)
          ? 'Added from favorite products.'
          : 'Added from product master.',
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${product.name} added to Shopping Assistant.'),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () {
          Navigator.pop(context);
          widget.onOpenShoppingList?.call();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final shown = products;
    final categories = catalog.products.map((item) => item.category).toSet();
    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        title: const Text('Product master'),
        actions: [
          IconButton(
            tooltip: favoritesOnly ? 'Show all products' : 'Show favorites',
            onPressed: () => setState(() => favoritesOnly = !favoritesOnly),
            icon: Icon(favoritesOnly ? Icons.star : Icons.star_border),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
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
                          'Products CartSense remembers',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${catalog.products.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${favorites.length} favorites Â· ${categories.length} categories',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.inventory_2_outlined,
                      color: _lime, size: 46),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              labelText: 'Search products',
              hintText: 'Tea, oil, paneer, pads...',
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
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All products'),
                selected: !favoritesOnly,
                onSelected: (_) => setState(() => favoritesOnly = false),
              ),
              ChoiceChip(
                label: const Text('Favorites'),
                selected: favoritesOnly,
                onSelected: (_) => setState(() => favoritesOnly = true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (catalog.products.isEmpty)
            const _ProductEmptyState()
          else if (shown.isEmpty)
            const _ProductEmptyState(
              message:
                  'No products match this view. Try another search or show all products.',
            )
          else
            ...shown.map((product) => Card(
                  child: ListTile(
                    leading: CategoryAvatar(category: product.category),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${product.category}\nLatest â‚¹${product.latestUnitPrice.toStringAsFixed(2)} at ${product.latestStore} Â· bought ${product.purchaseCount} times',
                    ),
                    isThreeLine: true,
                    trailing: SizedBox(
                      width: 102,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: favorites.contains(product.key)
                                ? 'Remove favorite'
                                : 'Favorite',
                            onPressed: () => _toggleFavorite(product),
                            icon: Icon(
                              favorites.contains(product.key)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: favorites.contains(product.key)
                                  ? Colors.orange
                                  : _green,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add to Shopping Assistant',
                            onPressed: () => _addToShoppingList(product),
                            icon: const Icon(Icons.add_circle, color: _green),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
        ],
      ),
      bottomNavigationBar: CartSenseFooterNav(
        selectedIndex: 2,
        activeShoppingCount: widget.activeShoppingCount,
        onDestinationSelected: (index) {
          if (index == 0) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 1) {
            widget.onScan?.call();
          } else if (index == 2) {
            Navigator.pop(context);
            widget.onOpenShoppingList?.call();
          } else if (index == 3) {
            widget.onOpenInsights?.call();
          }
        },
      ),
    );
  }
}

class _ProductEmptyState extends StatelessWidget {
  const _ProductEmptyState({
    this.message =
        'Scan and save receipts first. Products you buy will appear here automatically.',
  });

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: CartSenseColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.inventory_2_outlined, color: _green, size: 42),
              const SizedBox(height: 10),
              const Text(
                'No products yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
