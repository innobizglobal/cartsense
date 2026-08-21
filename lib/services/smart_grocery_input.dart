import '../models/product_catalog.dart';
import '../models/receipt.dart';

class SmartGroceryEntry {
  const SmartGroceryEntry({
    required this.originalText,
    required this.name,
    required this.quantity,
    required this.unitLabel,
    required this.category,
    this.matchedProduct,
    this.note = '',
  });

  final String originalText;
  final String name;
  final double quantity;
  final String unitLabel;
  final String category;
  final CatalogProduct? matchedProduct;
  final String note;

  bool get usedPastProduct =>
      matchedProduct != null && matchedProduct!.name == name;

  String get displayQuantity {
    final value = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
    return unitLabel.isEmpty ? value : '$value $unitLabel';
  }
}

class SmartGroceryInputParser {
  const SmartGroceryInputParser(this.catalog);

  final ProductCatalog catalog;

  List<SmartGroceryEntry> parse(String input) {
    final normalized = normalizeSpeechText(input);
    final parts = _splitEntries(normalized);
    return parts
        .map(_parseEntry)
        .where((entry) => entry.name.trim().isNotEmpty)
        .toList();
  }

  String normalizeSpeechText(String input) {
    var text = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\bcomma\b'), ',')
        .replaceAll(RegExp(r'\bfull stop\b'), ',')
        .replaceAll(RegExp(r'\bnext\b'), ',')
        .replaceAll(RegExp(r'\bthen\b'), ',')
        .replaceAll(RegExp(r'\bplus\b'), ',')
        .replaceAll(RegExp(r'\b(and|aur|और|మరియు|ఇంకా)\b'), ',');

    const replacements = {
      'नमक': 'salt',
      'चीनी': 'sugar',
      'दूध': 'milk',
      'चाय': 'tea',
      'तेल': 'oil',
      'साबुन': 'soap',
      'टूथपेस्ट': 'toothpaste',
      'पेस्ट': 'toothpaste',
      'चावल': 'rice',
      'आटा': 'atta',
      'दाल': 'dal',
      'पैड': 'pads',
      'uppu': 'salt',
      'ఉప్పు': 'salt',
      'పంచదార': 'sugar',
      'paalu': 'milk',
      'పాలు': 'milk',
      'టీ': 'tea',
      'నూనె': 'oil',
      'sabbu': 'soap',
      'సబ్బు': 'soap',
      'paste': 'toothpaste',
      'పేస్ట్': 'toothpaste',
      'బియ్యం': 'rice',
      'పప్పు': 'dal',
      'ప్యాడ్స్': 'pads',
      'और': ',',
      'మరియు': ',',
      'ఇంకా': ',',
      'दर्जन': 'dozen',
      'డజన్': 'dozen',
      'पैकेट': 'packets',
      'ప్యాకెట్': 'packets',
    };
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    const numberWords = {
      'zero': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
      'eleven': '11',
      'twelve': '12',
      'ek': '1',
      'एक': '1',
      'do': '2',
      'दो': '2',
      'teen': '3',
      'तीन': '3',
      'char': '4',
      'चार': '4',
      'paanch': '5',
      'पांच': '5',
      'okka': '1',
      'ఒకటి': '1',
      'rendu': '2',
      'రెండు': '2',
      'moodu': '3',
      'మూడు': '3',
      'nalugu': '4',
      'నాలుగు': '4',
      'aidu': '5',
      'ఐదు': '5',
    };
    for (final entry in numberWords.entries) {
      final isAscii = RegExp(r'^[a-z]+$').hasMatch(entry.key);
      text = isAscii
          ? text.replaceAll(
              RegExp('\\b${RegExp.escape(entry.key)}\\b'),
              entry.value,
            )
          : text.replaceAll(entry.key, entry.value);
    }

    text = text
        .replaceAll(RegExp(r'\bhalf\s*(?:kg|kilo|kilogram)\b'), '0.5 kg')
        .replaceAll(RegExp(r'\bquarter\s*(?:kg|kilo|kilogram)\b'), '0.25 kg')
        .replaceAll(RegExp(r'\bdozen\b'), '12 pcs')
        .replaceAll(RegExp(r'\bpacket\b'), 'packets')
        .replaceAll(RegExp(r'\bpieces?\b'), 'pcs')
        .replaceAll(RegExp(r'\bkilos?\b'), 'kg')
        .replaceAll(RegExp(r'\bkilograms?\b'), 'kg')
        .replaceAll(RegExp(r'\blitres?\b'), 'l')
        .replaceAll(RegExp(r'\bliters?\b'), 'l')
        .replaceAll(RegExp(r'\bltr\b'), 'l');

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _splitEntries(String text) {
    if (text.isEmpty) return const [];
    var splitReady = text
        .replaceAll(RegExp(r'[\n;]+'), ',')
        .replaceAll(RegExp(r'\.\s+'), ', ');

    splitReady = splitReady.replaceAllMapped(
      RegExp(
        r'(\b\d+(?:\.\d+)?\s*(?:kg|g|gm|ml|l|pcs|packets|packs|bars?|bottles?)\b)\s+(?=\S)',
      ),
      (match) => '${match.group(1)}, ',
    );

    return splitReady
        .split(RegExp(r',+'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  SmartGroceryEntry _parseEntry(String entry) {
    final cleaned = entry.replaceAll(RegExp(r'\s+'), ' ').trim();
    final quantity = _extractQuantity(cleaned);
    final nameText = _cleanName(cleaned, quantity);
    final alias = _canonicalAlias(nameText);
    final matched = _matchProduct(alias);
    final name = matched?.name ?? _titleCase(alias);
    final category = matched?.category ?? _inferCategory(alias);
    return SmartGroceryEntry(
      originalText: entry,
      name: name,
      quantity: quantity.quantity,
      unitLabel: quantity.unitLabel,
      category: category,
      matchedProduct: matched,
      note: matched == null
          ? 'Price will be learned from receipt scan.'
          : 'Matched from your past receipts.',
    );
  }

  ({double quantity, String unitLabel, String matchedText}) _extractQuantity(
    String text,
  ) {
    final match = RegExp(
      r'\b(\d+(?:\.\d+)?)\s*(kg|g|gm|ml|l|pcs|packets|packs|bars?|bottles?)?\b',
    ).firstMatch(text);
    if (match == null) {
      return (quantity: 1, unitLabel: '', matchedText: '');
    }
    final rawValue = double.tryParse(match.group(1) ?? '') ?? 1;
    final unit = match.group(2) ?? '';
    return (
      quantity: rawValue.clamp(.01, 999).toDouble(),
      unitLabel: _unitLabel(unit),
      matchedText: match.group(0) ?? '',
    );
  }

  String _cleanName(
    String text,
    ({double quantity, String unitLabel, String matchedText}) quantity,
  ) {
    var name = text;
    if (quantity.matchedText.isNotEmpty) {
      name = name.replaceFirst(quantity.matchedText, ' ');
    }
    name = name
        .replaceAll(
          RegExp(r'\b(?:need|buy|get|add|please|कृपया|चाहिए|కావాలి)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return name.isEmpty ? text.trim() : name;
  }

  String _canonicalAlias(String name) {
    final clean = name.toLowerCase().trim();
    const aliases = {
      'paste': 'toothpaste',
      'tooth paste': 'toothpaste',
      'brush': 'toothbrush',
      'soap': 'soap',
      'soaps': 'soap',
      'pad': 'pads',
      'napkin': 'pads',
      'napkins': 'pads',
      'atta': 'atta',
      'aata': 'atta',
      'dal': 'dal',
      'dhal': 'dal',
      'oil': 'oil',
      'tea powder': 'tea',
      'chai': 'tea',
      'namak': 'salt',
      'uppu': 'salt',
    };
    return aliases[clean] ?? clean;
  }

  CatalogProduct? _matchProduct(String query) {
    final exact = catalog.exactMatch(query);
    if (exact != null) return exact;
    final matches = catalog.search(query, limit: 4);
    if (matches.isEmpty) return null;
    final queryCategory = _inferCategory(query);
    final categoryMatch = matches.where(
      (product) => product.category == queryCategory,
    );
    if (queryCategory != GroceryCategory.other && categoryMatch.isNotEmpty) {
      return categoryMatch.first;
    }
    return matches.first;
  }

  String _inferCategory(String query) {
    final expanded = switch (query) {
      'toothpaste' => 'tooth paste colgate',
      'soap' => 'soap bathing soap',
      'pads' => 'sanitary pads napkins',
      'salt' => 'salt',
      'tea' => 'tea chai',
      'oil' => 'cooking oil',
      _ => query,
    };
    return GroceryCategory.infer(expanded);
  }

  String _unitLabel(String unit) => switch (unit) {
        'gm' => 'g',
        'packs' => 'packets',
        'pack' => 'packets',
        'bar' => 'pcs',
        'bars' => 'pcs',
        '' => '',
        _ => unit,
      };

  String _titleCase(String value) => value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
