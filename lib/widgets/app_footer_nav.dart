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
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          height: 82,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A0B3D2D),
                blurRadius: 18,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _FooterItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: t('home'),
                selected: selectedIndex == 0,
                onTap: () => onDestinationSelected(0),
              ),
              _FooterItem(
                icon: Icons.shopping_basket_outlined,
                selectedIcon: Icons.shopping_basket,
                label: t('shopping'),
                selected: selectedIndex == 1,
                badge: activeShoppingCount,
                onTap: () => onDestinationSelected(1),
              ),
              _CenterScanButton(
                label: t('scan'),
                selected: selectedIndex == 2,
                onTap: () => onDestinationSelected(2),
              ),
              _FooterItem(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                label: t('bills'),
                selected: selectedIndex == 3,
                onTap: () => onDestinationSelected(3),
              ),
              _FooterItem(
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights,
                label: t('spend'),
                selected: selectedIndex == 4,
                onTap: () => onDestinationSelected(4),
              ),
            ],
          ),
        ),
      );
}

class _FooterItem extends StatelessWidget {
  const _FooterItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: selected
                      ? const Color(0xFF145A43)
                      : const Color(0xFF5F6762),
                  size: 25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF145A43)
                      : const Color(0xFF5F6762),
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
}

class _CenterScanButton extends StatelessWidget {
  const _CenterScanButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(34),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFB7E45A)
                      : const Color(0xFF145A43),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33145A43),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.document_scanner,
                  color: selected ? const Color(0xFF145A43) : Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF145A43),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
}
