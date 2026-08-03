import 'package:flutter/material.dart';
import '../models/receipt.dart';
import '../theme/cartsense_theme.dart';

IconData groceryCategoryIcon(String category) => switch (category) {
      GroceryCategory.produce => Icons.eco_outlined,
      GroceryCategory.dairy => Icons.egg_alt_outlined,
      GroceryCategory.cookingOils => Icons.opacity_outlined,
      GroceryCategory.teaCoffee => Icons.local_cafe_outlined,
      GroceryCategory.pantry => Icons.inventory_2_outlined,
      GroceryCategory.beverages => Icons.local_drink_outlined,
      GroceryCategory.snacks => Icons.cookie_outlined,
      GroceryCategory.breakfastBakery => Icons.bakery_dining_outlined,
      GroceryCategory.frozenReady => Icons.ac_unit_outlined,
      GroceryCategory.household => Icons.cleaning_services_outlined,
      GroceryCategory.personalCare => Icons.spa_outlined,
      GroceryCategory.sanitaryCare => Icons.health_and_safety_outlined,
      GroceryCategory.babyCare => Icons.child_care_outlined,
      _ => Icons.shopping_basket_outlined,
    };

Color groceryCategoryColor(String category) => switch (category) {
      GroceryCategory.produce => const Color(0xFFDFF5D6),
      GroceryCategory.dairy => const Color(0xFFE2F0FF),
      GroceryCategory.cookingOils => const Color(0xFFFFF1C7),
      GroceryCategory.teaCoffee => const Color(0xFFEBDCCB),
      GroceryCategory.pantry => const Color(0xFFE8E0FF),
      GroceryCategory.beverages => const Color(0xFFD7F4F6),
      GroceryCategory.snacks => const Color(0xFFFFE2C6),
      GroceryCategory.breakfastBakery => const Color(0xFFFFE6D8),
      GroceryCategory.frozenReady => const Color(0xFFDDEEFF),
      GroceryCategory.household => const Color(0xFFE1F1EA),
      GroceryCategory.personalCare => const Color(0xFFFFE0EF),
      GroceryCategory.sanitaryCare => const Color(0xFFFFDFE6),
      GroceryCategory.babyCare => const Color(0xFFFFEBCF),
      _ => CartSenseColors.success,
    };

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(
      {super.key, required this.category, this.completed = false});

  final String category;
  final bool completed;

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: completed
              ? CartSenseColors.surfaceMuted
              : groceryCategoryColor(category),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: CartSenseColors.outline),
        ),
        child: Icon(
          completed ? Icons.check : groceryCategoryIcon(category),
          color: CartSenseColors.primary,
          size: 22,
        ),
      );
}
