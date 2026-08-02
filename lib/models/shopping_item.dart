import 'dart:convert';

class ShoppingItem {
  ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.category,
    required this.expectedUnitPrice,
    required this.bestUnitPrice,
    required this.bestStore,
    required this.createdAt,
    this.checked = false,
  });

  final String id;
  String name;
  double quantity;
  String category;
  double expectedUnitPrice;
  double bestUnitPrice;
  String bestStore;
  DateTime createdAt;
  bool checked;

  double get estimatedTotal => quantity * expectedUnitPrice;
  double get possibleSaving => ((expectedUnitPrice - bestUnitPrice) * quantity)
      .clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'category': category,
        'expectedUnitPrice': expectedUnitPrice,
        'bestUnitPrice': bestUnitPrice,
        'bestStore': bestStore,
        'createdAt': createdAt.toIso8601String(),
        'checked': checked,
      };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) => ShoppingItem(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        category: json['category']?.toString() ?? 'Other',
        expectedUnitPrice: (json['expectedUnitPrice'] as num?)?.toDouble() ?? 0,
        bestUnitPrice: (json['bestUnitPrice'] as num?)?.toDouble() ?? 0,
        bestStore: json['bestStore']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        checked: json['checked'] == true,
      );

  String encode() => jsonEncode(toJson());
  factory ShoppingItem.decode(String value) =>
      ShoppingItem.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
