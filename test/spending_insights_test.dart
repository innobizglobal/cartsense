import 'package:cartsense_lite/models/receipt.dart';
import 'package:cartsense_lite/models/spending_insights.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarises the selected month and finds the top category', () {
    final receipts = [
      Receipt(
        id: 'august',
        store: 'Fresh Mart',
        purchasedAt: DateTime(2026, 8, 2),
        printedTotal: 170,
        items: [
          ReceiptItem(
            name: 'Milk',
            category: GroceryCategory.dairy,
            quantity: 2,
            unitPrice: 50,
            discount: 0,
            confidence: 1,
          ),
          ReceiptItem(
            name: 'Rice',
            category: GroceryCategory.pantry,
            quantity: 1,
            unitPrice: 70,
            discount: 0,
            confidence: 1,
          ),
        ],
      ),
      Receipt(
        id: 'july',
        store: 'Old bill',
        purchasedAt: DateTime(2026, 7, 31),
        printedTotal: 999,
        items: [
          ReceiptItem(
            name: 'Coffee',
            quantity: 1,
            unitPrice: 999,
            discount: 0,
            confidence: 1,
          ),
        ],
      ),
    ];

    final insights = SpendingInsights.forMonth(
      receipts,
      month: DateTime(2026, 8),
    );

    expect(insights.billCount, 1);
    expect(insights.total, 170);
    expect(insights.topCategory, GroceryCategory.dairy);
    expect(insights.topCategoryTotal, 100);
  });

  test('infers useful grocery categories from product names', () {
    expect(GroceryCategory.infer('Heritage Paneer'), GroceryCategory.dairy);
    expect(GroceryCategory.infer('VIM Dish Wash'), GroceryCategory.household);
    expect(GroceryCategory.infer('Thums Up 750ml'), GroceryCategory.beverages);
    expect(
      GroceryCategory.infer('WHISPER BINDAZZ pads'),
      GroceryCategory.sanitaryCare,
    );
    expect(
      GroceryCategory.infer('Tetely Classic 250g'),
      GroceryCategory.teaCoffee,
    );
    expect(
      GroceryCategory.infer('Gold Drop Refined Oil 1L'),
      GroceryCategory.cookingOils,
    );
    expect(
      GroceryCategory.infer('Freedom Sunfl 1lt'),
      GroceryCategory.cookingOils,
    );
    expect(
      GroceryCategory.infer('Sanitary Pads XL'),
      GroceryCategory.sanitaryCare,
    );
    expect(
      GroceryCategory.infer('Dabur Glucose 200g'),
      GroceryCategory.snacks,
    );
    expect(
      GroceryCategory.infer('Heritage Panee'),
      GroceryCategory.dairy,
    );
    expect(
      GroceryCategory.infer('Gold Drop Oil 1L'),
      GroceryCategory.cookingOils,
    );
    expect(GroceryCategory.infer('coffe 200g'), GroceryCategory.teaCoffee);
    expect(GroceryCategory.infer('grapes 1kg'), GroceryCategory.produce);
    expect(GroceryCategory.infer('surf packet'), GroceryCategory.household);
  });
}
