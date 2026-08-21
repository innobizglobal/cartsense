import 'dart:convert';
import 'shopping_trip.dart';

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
  static const cookingOils = 'Cooking oils';
  static const teaCoffee = 'Tea & coffee';
  static const pantry = 'Pantry staples';
  static const beverages = 'Beverages';
  static const snacks = 'Snacks & sweets';
  static const breakfastBakery = 'Breakfast & bakery';
  static const frozenReady = 'Frozen & ready foods';
  static const household = 'Household';
  static const personalCare = 'Personal care';
  static const sanitaryCare = 'Sanitary care';
  static const babyCare = 'Baby care';
  static const other = 'Other';

  static const values = [
    produce,
    dairy,
    cookingOils,
    teaCoffee,
    pantry,
    beverages,
    snacks,
    breakfastBakery,
    frozenReady,
    household,
    personalCare,
    sanitaryCare,
    babyCare,
    other,
  ];

  static String infer(String productName) {
    final name =
        productName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (RegExp(
            r'\b(sanitary|whisper|wisper|nisper|bindazz|stayfree|stay free|sofy|kotex|carefree|niine|maxi pad|period pad|panty liner|tampon|pads|napkin|napkins)\b')
        .hasMatch(name)) {
      return sanitaryCare;
    }
    if (RegExp(
            r'\b(baby|diaper|diapers|pampers|mamy poko|huggies|cerelac|lactogen|nan pro|johnson baby)\b')
        .hasMatch(name)) {
      return babyCare;
    }
    if (RegExp(
            r'\b(tetley|tetely|tetly|tea|chai|tata tea|red label|taj mahal|wagh bakri|society tea|three roses|3 roses|brook bond|lipton|coffee|coffe|nescafe|bru|continental|sunrise)\b')
        .hasMatch(name)) {
      return teaCoffee;
    }
    if (RegExp(
            r'\b(gold drop|gold winner|sun drop|sundrop|fortune|freedom|saffola|dhara|gemini|sunflower|sunfl|groundnut|mustard oil|rice bran|soyabean oil|cooking oil|edible oil|refined oil|olive oil|coconut oil|oil)\b')
        .hasMatch(name)) {
      return cookingOils;
    }
    if (RegExp(
            r'\b(milk|paneer|panee|curd|yogurt|yoghurt|cheese|butter|ghee|cream|lassi|buttermilk|heritage|amul|nandini|mother dairy|milkymist|milky mist)\b')
        .hasMatch(name)) {
      return dairy;
    }
    if (RegExp(
            r'\b(apple|banana|mango|orange|grape|grapes|guava|papaya|watermelon|tomato|onion|potato|carrot|cabbage|beans|vegetable|vegetables|fruit|fruits|coriander|ginger|garlic|lemon)\b')
        .hasMatch(name)) {
      return produce;
    }
    if (RegExp(
            r'\b(bread|bun|rusk|cake|corn flakes|cornflakes|oats|muesli|cereal|idli batter|dosa batter|jam|honey|peanut butter|bournvita|boost|horlicks|complan)\b')
        .hasMatch(name)) {
      return breakfastBakery;
    }
    if (RegExp(
            r'\b(frozen|ready to eat|instant noodles|noodles|pasta|vermicelli|soup|maggie|maggi|yippee|paratha|nuggets|fries)\b')
        .hasMatch(name)) {
      return frozenReady;
    }
    if (RegExp(
            r'\b(rice|atta|flour|dal|dhal|pulse|salt|sugar|jaggery|masala|spice|ragi|sooji|suji|poha|besan|maida|rajma|chana|moong|toor|urad|aashirvaad|india gate|daawat)\b')
        .hasMatch(name)) {
      return pantry;
    }
    if (RegExp(
            r'\b(juice|water|soda|cola|limca|thums|sprite|fanta|maaza|drink|squash|energy drink)\b')
        .hasMatch(name)) {
      return beverages;
    }
    if (RegExp(
            r'\b(biscuit|biscuits|cookie|cookies|chips|chocolate|candy|sweet|namkeen|snack|wafer|mixture|kurkure|lays|hide seek|oreo|bourbon|parle|marie|good day|glucose|dark fantasy|sunfeast|britannia|haldiram)\b')
        .hasMatch(name)) {
      return snacks;
    }
    if (RegExp(
            r'\b(detergent|clean|dish|match|safe|floor|toilet|tissue|ariel|vim|comfort|surf|surf excel|rin|harpic|lizol|phenyl|garbage bag|foil|mosquito|good knight)\b')
        .hasMatch(name)) {
      return household;
    }
    if (RegExp(
            r'\b(soap|shampoo|conditioner|tooth|paste|brush|face wash|cream|lotion|dove|deodorant|deo|razor|shaving|hair oil|hand wash|sanitizer)\b')
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
    this.shoppingTrip,
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
  ShoppingTripResult? shoppingTrip;

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
        'shoppingTrip': shoppingTrip?.toJson(),
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
        shoppingTrip: json['shoppingTrip'] is Map
            ? ShoppingTripResult.fromJson(
                Map<String, dynamic>.from(json['shoppingTrip'] as Map))
            : null,
      );

  String encode() => jsonEncode(toJson());
  factory Receipt.decode(String value) =>
      Receipt.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
