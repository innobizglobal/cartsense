import 'package:flutter/material.dart';
import '../services/language_store.dart';

class CartSenseFooterNav extends StatelessWidget {
  const CartSenseFooterNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.activeShoppingCount = 0,
    this.languageCode = 'en',
  });

  final int selectedIndex;
  final int activeShoppingCount;
  final ValueChanged<int> onDestinationSelected;
  final String languageCode;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.document_scanner_outlined),
            selectedIcon: const Icon(Icons.document_scanner),
            label: t('scan'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeShoppingCount > 0,
              label: Text('$activeShoppingCount'),
              child: const Icon(Icons.shopping_basket_outlined),
            ),
            selectedIcon: const Icon(Icons.shopping_basket),
            label: t('list'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: t('insights'),
          ),
        ],
      );
}
