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
              : CartSenseColors.success,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          completed ? Icons.check : groceryCategoryIcon(category),
          color: CartSenseColors.primary,
          size: 22,
        ),
      );
}
