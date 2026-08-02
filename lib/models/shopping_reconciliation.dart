import 'receipt.dart';
import 'savings_intelligence.dart';
import 'shopping_item.dart';
import 'shopping_trip.dart';

class ShoppingReconciliation {
  const ShoppingReconciliation._();

  static Map<String, int> suggest(
    List<ShoppingItem> planned,
    Receipt receipt,
  ) {
    final candidates = <_Candidate>[];
    for (final item in planned) {
      for (var index = 0; index < receipt.items.length; index++) {
        final score = matchScore(item, receipt.items[index]);
        if (score >= .6) {
          candidates.add(_Candidate(item.id, index, score));
        }
      }
    }
    candidates.sort((left, right) => right.score.compareTo(left.score));
    final assignments = <String, int>{};
    final usedReceiptRows = <int>{};
    for (final candidate in candidates) {
      if (assignments.containsKey(candidate.plannedItemId) ||
          usedReceiptRows.contains(candidate.receiptIndex)) {
        continue;
      }
      assignments[candidate.plannedItemId] = candidate.receiptIndex;
      usedReceiptRows.add(candidate.receiptIndex);
    }
    return assignments;
  }

  static double matchScore(ShoppingItem planned, ReceiptItem purchased) {
    final plannedKey = normalizedProductName(planned.name);
    final purchasedKey = normalizedProductName(purchased.name);
    if (plannedKey.isEmpty || purchasedKey.isEmpty) return 0;
    var score = 0.0;
    if (plannedKey == purchasedKey) {
      score = 1;
    } else if ((plannedKey.length >= 3 && purchasedKey.contains(plannedKey)) ||
        (purchasedKey.length >= 3 && plannedKey.contains(purchasedKey))) {
      score = .88;
    } else {
      final plannedTokens =
          plannedKey.split(' ').where((token) => token.length > 1).toSet();
      final purchasedTokens =
          purchasedKey.split(' ').where((token) => token.length > 1).toSet();
      final shared = plannedTokens.intersection(purchasedTokens).length;
      if (shared > 0) {
        score = .52 +
            .3 *
                (shared /
                    (plannedTokens.length < purchasedTokens.length
                        ? plannedTokens.length
                        : purchasedTokens.length));
      }
    }

    final sameCategory = planned.category != GroceryCategory.other &&
        planned.category == purchased.category;
    if (sameCategory) {
      if (_isGenericCategoryRequest(plannedKey, planned.category)) {
        score = score < .76 ? .76 : score;
      } else if (score > 0) {
        score += .07;
      } else {
        score = .5;
      }
    }

    final actualUnitPrice = purchased.unitPrice > 0
        ? purchased.unitPrice
        : purchased.quantity > 0
            ? purchased.total / purchased.quantity
            : 0;
    if (score >= .5 && planned.expectedUnitPrice > 0 && actualUnitPrice > 0) {
      final difference = (actualUnitPrice - planned.expectedUnitPrice).abs() /
          planned.expectedUnitPrice;
      if (difference <= .2) {
        score += .08;
      } else if (difference <= .5) {
        score += .03;
      }
    }
    return score.clamp(0, 1);
  }

  static ShoppingTripResult buildResult({
    required List<ShoppingItem> planned,
    required Receipt receipt,
    required Map<String, int> assignments,
    DateTime? reconciledAt,
  }) {
    final matches = <TripMatchSnapshot>[];
    final missing = <TripPlannedSnapshot>[];
    final usedReceiptRows = <int>{};
    for (final item in planned) {
      final index = assignments[item.id];
      if (index == null || index < 0 || index >= receipt.items.length) {
        missing.add(TripPlannedSnapshot(
          plannedItemId: item.id,
          name: item.name,
          category: item.category,
          quantity: item.quantity,
          expectedTotal: item.estimatedTotal,
        ));
        continue;
      }
      final purchased = receipt.items[index];
      usedReceiptRows.add(index);
      matches.add(TripMatchSnapshot(
        plannedItemId: item.id,
        plannedName: item.name,
        purchasedName: purchased.name,
        category: purchased.category,
        plannedQuantity: item.quantity,
        purchasedQuantity: purchased.quantity,
        expectedTotal: item.estimatedTotal,
        actualTotal: purchased.total,
        confidence: matchScore(item, purchased),
      ));
    }
    final unplanned = <TripUnexpectedSnapshot>[];
    for (var index = 0; index < receipt.items.length; index++) {
      if (usedReceiptRows.contains(index)) continue;
      final item = receipt.items[index];
      unplanned.add(TripUnexpectedSnapshot(
        name: item.name,
        category: item.category,
        quantity: item.quantity,
        actualTotal: item.total,
      ));
    }
    return ShoppingTripResult(
      receiptId: receipt.id,
      store: receipt.store,
      reconciledAt: reconciledAt ?? DateTime.now(),
      billTotal: receipt.printedTotal > 0
          ? receipt.printedTotal
          : receipt.calculatedTotal,
      plannedEstimate:
          planned.fold(0, (total, item) => total + item.estimatedTotal),
      matches: matches,
      missing: missing,
      unplanned: unplanned,
    );
  }

  static bool _isGenericCategoryRequest(String key, String category) {
    const genericTerms = {
      GroceryCategory.teaCoffee: {'tea', 'chai', 'coffee'},
      GroceryCategory.cookingOils: {'oil', 'cooking oil', 'edible oil'},
      GroceryCategory.dairy: {'milk', 'curd', 'cheese', 'paneer'},
      GroceryCategory.produce: {'fruit', 'fruits', 'vegetable', 'vegetables'},
      GroceryCategory.beverages: {'drink', 'juice', 'water'},
      GroceryCategory.snacks: {'snack', 'snacks', 'biscuit', 'biscuits'},
      GroceryCategory.household: {'cleaner', 'detergent'},
      GroceryCategory.sanitaryCare: {'pad', 'pads', 'sanitary pads'},
    };
    return genericTerms[category]?.contains(key) == true;
  }
}

class _Candidate {
  const _Candidate(this.plannedItemId, this.receiptIndex, this.score);

  final String plannedItemId;
  final int receiptIndex;
  final double score;
}
