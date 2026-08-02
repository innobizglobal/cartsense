class TripMatchSnapshot {
  const TripMatchSnapshot({
    required this.plannedItemId,
    required this.plannedName,
    required this.purchasedName,
    required this.category,
    required this.plannedQuantity,
    required this.purchasedQuantity,
    required this.expectedTotal,
    required this.actualTotal,
    required this.confidence,
  });

  final String plannedItemId;
  final String plannedName;
  final String purchasedName;
  final String category;
  final double plannedQuantity;
  final double purchasedQuantity;
  final double expectedTotal;
  final double actualTotal;
  final double confidence;

  double get difference => actualTotal - expectedTotal;

  Map<String, dynamic> toJson() => {
        'plannedItemId': plannedItemId,
        'plannedName': plannedName,
        'purchasedName': purchasedName,
        'category': category,
        'plannedQuantity': plannedQuantity,
        'purchasedQuantity': purchasedQuantity,
        'expectedTotal': expectedTotal,
        'actualTotal': actualTotal,
        'confidence': confidence,
      };

  factory TripMatchSnapshot.fromJson(Map<String, dynamic> json) =>
      TripMatchSnapshot(
        plannedItemId: json['plannedItemId']?.toString() ?? '',
        plannedName: json['plannedName']?.toString() ?? '',
        purchasedName: json['purchasedName']?.toString() ?? '',
        category: json['category']?.toString() ?? 'Other',
        plannedQuantity: (json['plannedQuantity'] as num?)?.toDouble() ?? 1,
        purchasedQuantity: (json['purchasedQuantity'] as num?)?.toDouble() ?? 1,
        expectedTotal: (json['expectedTotal'] as num?)?.toDouble() ?? 0,
        actualTotal: (json['actualTotal'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
}

class TripPlannedSnapshot {
  const TripPlannedSnapshot({
    required this.plannedItemId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.expectedTotal,
  });

  final String plannedItemId;
  final String name;
  final String category;
  final double quantity;
  final double expectedTotal;

  Map<String, dynamic> toJson() => {
        'plannedItemId': plannedItemId,
        'name': name,
        'category': category,
        'quantity': quantity,
        'expectedTotal': expectedTotal,
      };

  factory TripPlannedSnapshot.fromJson(Map<String, dynamic> json) =>
      TripPlannedSnapshot(
        plannedItemId: json['plannedItemId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? 'Other',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        expectedTotal: (json['expectedTotal'] as num?)?.toDouble() ?? 0,
      );
}

class TripUnexpectedSnapshot {
  const TripUnexpectedSnapshot({
    required this.name,
    required this.category,
    required this.quantity,
    required this.actualTotal,
  });

  final String name;
  final String category;
  final double quantity;
  final double actualTotal;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'quantity': quantity,
        'actualTotal': actualTotal,
      };

  factory TripUnexpectedSnapshot.fromJson(Map<String, dynamic> json) =>
      TripUnexpectedSnapshot(
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? 'Other',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        actualTotal: (json['actualTotal'] as num?)?.toDouble() ?? 0,
      );
}

class ShoppingTripResult {
  const ShoppingTripResult({
    required this.receiptId,
    required this.store,
    required this.reconciledAt,
    required this.billTotal,
    required this.plannedEstimate,
    required this.matches,
    required this.missing,
    required this.unplanned,
  });

  final String receiptId;
  final String store;
  final DateTime reconciledAt;
  final double billTotal;
  final double plannedEstimate;
  final List<TripMatchSnapshot> matches;
  final List<TripPlannedSnapshot> missing;
  final List<TripUnexpectedSnapshot> unplanned;

  double get matchedExpectedTotal =>
      matches.fold(0, (total, item) => total + item.expectedTotal);
  double get matchedActualTotal =>
      matches.fold(0, (total, item) => total + item.actualTotal);
  double get unplannedTotal =>
      unplanned.fold(0, (total, item) => total + item.actualTotal);
  double get matchedPriceDifference =>
      matchedActualTotal - matchedExpectedTotal;

  Map<String, dynamic> toJson() => {
        'receiptId': receiptId,
        'store': store,
        'reconciledAt': reconciledAt.toIso8601String(),
        'billTotal': billTotal,
        'plannedEstimate': plannedEstimate,
        'matches': matches.map((item) => item.toJson()).toList(),
        'missing': missing.map((item) => item.toJson()).toList(),
        'unplanned': unplanned.map((item) => item.toJson()).toList(),
      };

  factory ShoppingTripResult.fromJson(Map<String, dynamic> json) =>
      ShoppingTripResult(
        receiptId: json['receiptId']?.toString() ?? '',
        store: json['store']?.toString() ?? 'Unknown store',
        reconciledAt:
            DateTime.tryParse(json['reconciledAt']?.toString() ?? '') ??
                DateTime.now(),
        billTotal: (json['billTotal'] as num?)?.toDouble() ?? 0,
        plannedEstimate: (json['plannedEstimate'] as num?)?.toDouble() ?? 0,
        matches: ((json['matches'] as List?) ?? [])
            .map((item) => TripMatchSnapshot.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        missing: ((json['missing'] as List?) ?? [])
            .map((item) => TripPlannedSnapshot.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        unplanned: ((json['unplanned'] as List?) ?? [])
            .map((item) => TripUnexpectedSnapshot.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}
