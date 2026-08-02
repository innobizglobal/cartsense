import 'dart:convert';

class ReceiptItem {
  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.confidence,
  });

  String name;
  double quantity;
  double unitPrice;
  double discount;
  double confidence;

  double get total => (quantity * unitPrice) - discount;
  bool get needsReview => confidence < 0.8;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'discount': discount,
        'confidence': confidence,
      };

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
        name: json['name']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
}

class Receipt {
  Receipt({
    required this.id,
    required this.store,
    required this.purchasedAt,
    required this.items,
    required this.printedTotal,
    this.imagePath,
  });

  String id;
  String store;
  DateTime purchasedAt;
  List<ReceiptItem> items;
  double printedTotal;
  String? imagePath;

  double get calculatedTotal => items.fold(0, (sum, item) => sum + item.total);
  double get difference => calculatedTotal - printedTotal;
  bool get reconciled => difference.abs() <= 0.05;

  Map<String, dynamic> toJson() => {
        'id': id,
        'store': store,
        'purchasedAt': purchasedAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'printedTotal': printedTotal,
        'imagePath': imagePath,
      };

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        id: json['id'].toString(),
        store: json['store']?.toString() ?? 'Unknown store',
        purchasedAt: DateTime.tryParse(json['purchasedAt']?.toString() ?? '') ??
            DateTime.now(),
        items: ((json['items'] as List?) ?? [])
            .map((item) =>
                ReceiptItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        printedTotal: (json['printedTotal'] as num?)?.toDouble() ?? 0,
        imagePath: json['imagePath']?.toString(),
      );

  String encode() => jsonEncode(toJson());
  factory Receipt.decode(String value) =>
      Receipt.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
