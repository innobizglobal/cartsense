import 'dart:convert';

class ReceiptItem {
  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.confidence,
    this.parsedLineTotal,
    String? category,
  }) : category = category ?? GroceryCategory.infer(name);

  String name;
  double quantity;
  double unitPrice;
  double discount;
  double confidence;
  double? parsedLineTotal;
  String category;

  double get total => parsedLineTotal ?? (quantity * unitPrice) - discount;
  bool get needsReview => confidence < 0.8;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'discount': discount,
        'confidence': confidence,
        'parsedLineTotal': parsedLineTotal,
        'category': category,
      };

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
        name: json['name']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        parsedLineTotal: (json['parsedLineTotal'] as num?)?.toDouble(),
        category: json['category']?.toString(),
      );
}

class GroceryCategory {
  static const produce = 'Fruit & vegetables';
  static const dairy = 'Dairy & chilled';
  static const pantry = 'Pantry staples';
  static const beverages = 'Beverages';
  static const snacks = 'Snacks & sweets';
  static const household = 'Household';
  static const personalCare = 'Personal care';
  static const other = 'Other';

  static const values = [
    produce,
    dairy,
    pantry,
    beverages,
    snacks,
    household,
    personalCare,
    other,
  ];

  static String infer(String productName) {
    final name = productName.toLowerCase();
    if (RegExp(r'\b(milk|paneer|curd|yogurt|cheese|butter|ghee|cream)\b')
        .hasMatch(name)) {
      return dairy;
    }
    if (RegExp(
            r'\b(apple|banana|mango|orange|grape|tomato|onion|potato|carrot|vegetable|fruit)\b')
        .hasMatch(name)) {
      return produce;
    }
    if (RegExp(
            r'\b(rice|atta|flour|dal|pulse|oil|salt|sugar|masala|spice|ragi)\b')
        .hasMatch(name)) {
      return pantry;
    }
    if (RegExp(r'\b(tea|coffee|juice|water|cola|limca|thums|drink)\b')
        .hasMatch(name)) {
      return beverages;
    }
    if (RegExp(
            r'\b(biscuit|cookie|chips|chocolate|candy|sweet|namkeen|snack)\b')
        .hasMatch(name)) {
      return snacks;
    }
    if (RegExp(
            r'\b(detergent|clean|dish|match|safe|floor|toilet|tissue|ariel|vim|comfort)\b')
        .hasMatch(name)) {
      return household;
    }
    if (RegExp(
            r'\b(soap|shampoo|tooth|paste|brush|cream|lotion|dove|deodorant)\b')
        .hasMatch(name)) {
      return personalCare;
    }
    return other;
  }
}

class Receipt {
  Receipt({
    required this.id,
    required this.store,
    required this.purchasedAt,
    required this.items,
    required this.printedTotal,
    this.imagePath,
    this.printedItemCount,
    this.printedQuantityTotal,
    this.taxTotal = 0,
    this.billDiscount = 0,
    this.otherCharges = 0,
    this.overallConfidence = 0.65,
    this.warnings = const [],
    this.recognitionSource = 'on_device',
  });

  String id;
  String store;
  DateTime purchasedAt;
  List<ReceiptItem> items;
  double printedTotal;
  String? imagePath;
  int? printedItemCount;
  double? printedQuantityTotal;
  double taxTotal;
  double billDiscount;
  double otherCharges;
  double overallConfidence;
  List<String> warnings;
  String recognitionSource;

  double get itemSubtotal => items.fold(0, (sum, item) => sum + item.total);
  double get calculatedTotal =>
      itemSubtotal + taxTotal + otherCharges - billDiscount;
  double get difference => calculatedTotal - printedTotal;
  bool get reconciled => difference.abs() <= 0.05;
  bool get isAiEnhanced => recognitionSource == 'ai_enhanced';
  bool get itemCountMatches =>
      printedItemCount == null || printedItemCount == items.length;
  bool get confidentlyReconciled =>
      reconciled &&
      items.isNotEmpty &&
      itemCountMatches &&
      overallConfidence >= 0.82 &&
      items.every((item) => item.confidence >= 0.7);
  int get reviewItemCount => items.where((item) => item.needsReview).length;
  bool get reviewComplete => reviewItemCount == 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'store': store,
        'purchasedAt': purchasedAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'printedTotal': printedTotal,
        'imagePath': imagePath,
        'printedItemCount': printedItemCount,
        'printedQuantityTotal': printedQuantityTotal,
        'taxTotal': taxTotal,
        'billDiscount': billDiscount,
        'otherCharges': otherCharges,
        'overallConfidence': overallConfidence,
        'warnings': warnings,
        'recognitionSource': recognitionSource,
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
        printedItemCount: (json['printedItemCount'] as num?)?.toInt(),
        printedQuantityTotal:
            (json['printedQuantityTotal'] as num?)?.toDouble(),
        taxTotal: (json['taxTotal'] as num?)?.toDouble() ?? 0,
        billDiscount: (json['billDiscount'] as num?)?.toDouble() ?? 0,
        otherCharges: (json['otherCharges'] as num?)?.toDouble() ?? 0,
        overallConfidence:
            (json['overallConfidence'] as num?)?.toDouble() ?? 0.65,
        warnings: ((json['warnings'] as List?) ?? [])
            .map((warning) => warning.toString())
            .toList(),
        recognitionSource: json['recognitionSource']?.toString() ?? 'on_device',
      );

  String encode() => jsonEncode(toJson());
  factory Receipt.decode(String value) =>
      Receipt.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
