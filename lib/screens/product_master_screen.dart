import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_catalog.dart';
import '../models/receipt.dart';
import '../models/shopping_item.dart';
import '../services/language_store.dart';
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
  AppLanguage language = AppLanguage.english;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
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

  Future<void> _loadLanguage() async {
    final saved = await LanguageStore().load();
    if (mounted) setState(() => language = saved);
  }

  String t(String key) => appText(language.code, key);

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
          : 'Added from usual items.',
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${product.name} added to Shopping Assistant.'),
      action: SnackBarAction(
        label: t('open'),
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
        title: Text(t('productMaster')),
        actions: [
          IconButton(
            tooltip: favoritesOnly ? t('showAllProducts') : t('showFavorites'),
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
                        Text(
                          t('productsRemembered'),
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
                          '${favorites.length} ${t('favorites')} · ${categories.length} ${t('categories')}',
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
              labelText: t('searchProducts'),
              hintText: t('searchProductsHint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: t('clearSearch'),
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
                label: Text(t('allProducts')),
                selected: !favoritesOnly,
                onSelected: (_) => setState(() => favoritesOnly = false),
              ),
              ChoiceChip(
                label: Text(t('favorites')),
                selected: favoritesOnly,
                onSelected: (_) => setState(() => favoritesOnly = true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (catalog.products.isEmpty)
            _ProductEmptyState(languageCode: language.code)
          else if (shown.isEmpty)
            _ProductEmptyState(
              languageCode: language.code,
              message: t('noProductsMatch'),
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
                      '${categoryText(language.code, product.category)}\n'
                      '${t('latest')} ₹${product.latestUnitPrice.toStringAsFixed(2)} '
                      '${t('at')} ${product.latestStore} · '
                      '${product.purchaseCount} ${t('boughtTimes')}',
                    ),
                    isThreeLine: true,
                    trailing: SizedBox(
                      width: 102,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: favorites.contains(product.key)
                                ? t('removeFavorite')
                                : t('favorite'),
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
                            tooltip: t('addToShopping'),
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
    required this.languageCode,
    this.message,
  });

  final String languageCode;
  final String? message;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) => Card(
        color: CartSenseColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.inventory_2_outlined, color: _green, size: 42),
              const SizedBox(height: 10),
              Text(
                t('noProductsYet'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(message ?? t('noProductsYetBody'),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
