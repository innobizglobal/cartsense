import 'package:flutter/material.dart';

class CartSenseFooterNav extends StatelessWidget {
  const CartSenseFooterNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.activeShoppingCount = 0,
  });

  final int selectedIndex;
  final int activeShoppingCount;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
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
      );
}
