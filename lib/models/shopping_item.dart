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
    this.latestStore = '',
    this.note = '',
    this.remindAt,
    this.completedAt,
    this.sourceReceiptId,
    this.reconciledReceiptId,
    this.purchasedName,
    this.actualUnitPrice,
    this.checked = false,
  });

  final String id;
  String name;
  double quantity;
  String category;
  double expectedUnitPrice;
  double bestUnitPrice;
  String bestStore;
  String latestStore;
  String note;
  DateTime? remindAt;
  DateTime? completedAt;
  String? sourceReceiptId;
  String? reconciledReceiptId;
  String? purchasedName;
  double? actualUnitPrice;
  DateTime createdAt;
  bool checked;

  double get estimatedTotal => quantity * expectedUnitPrice;
  double get possibleSaving => ((expectedUnitPrice - bestUnitPrice) * quantity)
      .clamp(0, double.infinity);
  bool isReminderDue(DateTime now) =>
      !checked && remindAt != null && !remindAt!.isAfter(now);
  int get notificationId => id.hashCode & 0x7fffffff;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'category': category,
        'expectedUnitPrice': expectedUnitPrice,
        'bestUnitPrice': bestUnitPrice,
        'bestStore': bestStore,
        'latestStore': latestStore,
        'note': note,
        'remindAt': remindAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'sourceReceiptId': sourceReceiptId,
        'reconciledReceiptId': reconciledReceiptId,
        'purchasedName': purchasedName,
        'actualUnitPrice': actualUnitPrice,
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
        latestStore: json['latestStore']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
        remindAt: DateTime.tryParse(json['remindAt']?.toString() ?? ''),
        completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
        sourceReceiptId: json['sourceReceiptId']?.toString(),
        reconciledReceiptId: json['reconciledReceiptId']?.toString(),
        purchasedName: json['purchasedName']?.toString(),
        actualUnitPrice: (json['actualUnitPrice'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        checked: json['checked'] == true,
      );

  String encode() => jsonEncode(toJson());
  factory ShoppingItem.decode(String value) =>
      ShoppingItem.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
