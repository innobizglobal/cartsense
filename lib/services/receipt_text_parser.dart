import '../models/receipt.dart';

class ReceiptTextParser {
  const ReceiptTextParser();

  static final _amountPattern = RegExp(
    r'(?<![A-Za-z0-9])(-?\d[\d,]*(?:\.\d{1,3})?)(?![A-Za-z0-9])',
  );
  static final _datePattern = RegExp(
    r'\b(\d{1,4})[./-](\d{1,2})[./-](\d{1,4})\b',
  );
  static final _letters = RegExp(r'[A-Za-z]');
  static final _nonItemWords = RegExp(
    r'\b(sub\s*total|grand\s*total|total|tax|gst|cgst|sgst|igst|amount|cash|change|round(?:ing)?|saving|discount|balance|tender|payment|invoice|receipt|bill\s*no|phone|mobile|fssai|date|time)\b',
    caseSensitive: false,
  );

  Receipt parse(
    String rawText, {
    String? imagePath,
    DateTime? now,
  }) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final items = <ReceiptItem>[];

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (_isDiscountLine(lower)) {
        final discount = _lastAmount(line);
        if (discount != null && discount > 0 && items.isNotEmpty) {
          items.last.discount += discount;
          items.last.confidence =
              items.last.confidence.clamp(0, 0.78).toDouble();
        }
        continue;
      }
      final item = _parseItem(line);
      if (item != null) items.add(item);
    }

    final calculatedTotal =
        items.fold<double>(0, (sum, item) => sum + item.total);
    final printedTotal = _findPrintedTotal(lines) ?? calculatedTotal;
    final timestamp = now ?? DateTime.now();

    return Receipt(
      id: timestamp.microsecondsSinceEpoch.toString(),
      store: _findStore(lines),
      purchasedAt: _findDate(lines) ?? timestamp,
      items: items,
      printedTotal: printedTotal,
      imagePath: imagePath,
    );
  }

  ReceiptItem? _parseItem(String source) {
    var line = source.replaceFirst(RegExp(r'^\s*\d{4,}\s+'), '');
    if (_nonItemWords.hasMatch(line)) return null;

    final matches = _amountPattern.allMatches(line).toList();
    if (matches.isEmpty) return null;
    final last = matches.last;
    if (line.substring(last.end).trim().length > 2) return null;

    var name = line.substring(0, matches.first.start).trim();
    name = name
        .replaceAll(RegExp(r'[-:*]+$'), '')
        .replaceAll(RegExp(r'\s+[xX]$'), '')
        .trim();
    if (name.length < 2 || !_letters.hasMatch(name)) return null;

    final values = matches
        .map((match) => _toAmount(match.group(1)!))
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;

    final lineTotal = values.last.abs();
    if (lineTotal <= 0) return null;

    var quantity = 1.0;
    var unitPrice = lineTotal;
    var confidence = 0.72;
    if (values.length >= 3) {
      final proposedQuantity = values[values.length - 3];
      final proposedUnitPrice = values[values.length - 2];
      final proposedTotal = proposedQuantity * proposedUnitPrice;
      final tolerance = (lineTotal * 0.04).clamp(0.10, 1.00);
      if (proposedQuantity > 0 &&
          proposedQuantity <= 999 &&
          (proposedTotal - lineTotal).abs() <= tolerance) {
        quantity = proposedQuantity;
        unitPrice = proposedUnitPrice;
        confidence = 0.92;
      }
    } else if (values.length == 2 &&
        RegExp(r'\b\d+(?:\.\d+)?\s*[xX]\s*').hasMatch(line)) {
      final proposedQuantity = values.first;
      if (proposedQuantity > 0 && proposedQuantity <= 999) {
        quantity = proposedQuantity;
        unitPrice = lineTotal / quantity;
        confidence = 0.84;
      }
    }

    return ReceiptItem(
      name: name,
      quantity: quantity,
      unitPrice: unitPrice,
      discount: 0,
      confidence: confidence,
    );
  }

  String _findStore(List<String> lines) {
    for (final line in lines.take(8)) {
      final lower = line.toLowerCase();
      if (line.length < 3 ||
          line.length > 48 ||
          !_letters.hasMatch(line) ||
          _amountPattern.hasMatch(line) ||
          _datePattern.hasMatch(line) ||
          RegExp(
            r'\b(invoice|receipt|tax|gstin|fssai|phone|mobile|address|cashier|date|time|bill)\b',
            caseSensitive: false,
          ).hasMatch(lower)) {
        continue;
      }
      return _titleCase(line);
    }
    return 'Scanned grocery bill';
  }

  DateTime? _findDate(List<String> lines) {
    for (final line in lines) {
      final match = _datePattern.firstMatch(line);
      if (match == null) continue;
      var first = int.tryParse(match.group(1)!);
      final middle = int.tryParse(match.group(2)!);
      var last = int.tryParse(match.group(3)!);
      if (first == null || middle == null || last == null) continue;

      late int year;
      late int month;
      late int day;
      if (match.group(1)!.length == 4) {
        year = first;
        month = middle;
        day = last;
      } else {
        day = first;
        month = middle;
        year = last < 100 ? 2000 + last : last;
      }
      if (year < 2000 ||
          year > 2100 ||
          month < 1 ||
          month > 12 ||
          day < 1 ||
          day > 31) {
        continue;
      }
      final parsed = DateTime(year, month, day);
      if (parsed.year == year && parsed.month == month && parsed.day == day) {
        return parsed;
      }
    }
    return null;
  }

  double? _findPrintedTotal(List<String> lines) {
    final preferred = RegExp(
      r'\b(grand\s*total|net\s*(?:amount|total)|amount\s*payable|total\s*amount|balance\s*due)\b',
      caseSensitive: false,
    );
    for (final line in lines.reversed) {
      if (preferred.hasMatch(line)) {
        final amount = _lastAmount(line);
        if (amount != null && amount > 0) return amount;
      }
    }
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (RegExp(r'\btotal\b').hasMatch(lower) &&
          !RegExp(r'\bsub\s*total\b').hasMatch(lower)) {
        final amount = _lastAmount(line);
        if (amount != null && amount > 0) return amount;
      }
    }
    return null;
  }

  bool _isDiscountLine(String lower) =>
      RegExp(r'\b(discount|saving|you saved)\b').hasMatch(lower) &&
      !RegExp(r'\btotal\b').hasMatch(lower);

  double? _lastAmount(String line) {
    final matches = _amountPattern.allMatches(line).toList();
    if (matches.isEmpty) return null;
    return _toAmount(matches.last.group(1)!);
  }

  double? _toAmount(String value) =>
      double.tryParse(value.replaceAll(',', '').trim());

  String _titleCase(String value) => value
      .split(' ')
      .map((word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');
}
