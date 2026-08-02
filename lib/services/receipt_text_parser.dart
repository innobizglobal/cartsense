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
    r'\b(sub\s*total|grand\s*total|total|tax|gst|gstin|cgst|sgst|igst|amount|cash|change|round(?:ing)?|saving|discount|balance|tender|payment|invoice|receipt|bill\s*no|phone|mobile|fssai|date|time|it[ea][mn]s?|particulars?|description|qty|quantity|rate|mrp|hsn|sac|barcode|sku|article|cashier|customer|member|loyalty|address|pincode|website|email|thank\s*you)\b',
    caseSensitive: false,
  );
  static final _administrativeFragments = RegExp(
    r'(telangana|andhra\s*pradesh|karnataka|tamil\s*nadu|maharashtra|www\.|https?://|@\w+\.\w+|(?:inv|von)\s*[:.#-]?\s*no)',
    caseSensitive: false,
  );
  static final _longIdentifier = RegExp(
    r'\b(?=[A-Za-z0-9]{7,}\b)(?=(?:[A-Za-z]*\d){5})[A-Za-z0-9]+\b',
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
    final printedTotal = _findPrintedTotal(lines);
    final itemHeaderIndex = lines.indexWhere(_isItemHeader);
    final items = <ReceiptItem>[];
    String? pendingName;

    for (var index = itemHeaderIndex < 0 ? 0 : itemHeaderIndex + 1;
        index < lines.length;
        index++) {
      final line = lines[index];
      final lower = line.toLowerCase();
      if (items.isNotEmpty && _isSummaryStart(lower)) break;
      if (_isDiscountLine(lower)) {
        final discount = _lastAmount(line);
        if (discount != null && discount > 0 && items.isNotEmpty) {
          items.last.discount += discount;
          items.last.confidence =
              items.last.confidence.clamp(0, 0.78).toDouble();
        }
        pendingName = null;
        continue;
      }
      if (_isAdministrativeLine(line)) {
        pendingName = null;
        continue;
      }

      var item = _parseItem(line, printedTotal: printedTotal);
      if (item == null && pendingName != null) {
        item = _parseItem(
          '$pendingName $line',
          printedTotal: printedTotal,
        );
      }
      if (item != null) {
        items.add(item);
        pendingName = null;
      } else if ((itemHeaderIndex >= 0 || items.isNotEmpty) &&
          _isPossibleProductName(line)) {
        pendingName = line;
      } else {
        pendingName = null;
      }
    }

    final calculatedTotal =
        items.fold<double>(0, (sum, item) => sum + item.total);
    final resolvedPrintedTotal = printedTotal ?? calculatedTotal;
    final timestamp = now ?? DateTime.now();

    return Receipt(
      id: timestamp.microsecondsSinceEpoch.toString(),
      store: _findStore(lines),
      purchasedAt: _findDate(lines) ?? timestamp,
      items: items,
      printedTotal: resolvedPrintedTotal,
      imagePath: imagePath,
    );
  }

  ReceiptItem? _parseItem(String source, {double? printedTotal}) {
    var line = source
        .replaceFirst(RegExp(r'^\s*(?:\d{4,14}|\d{1,3}[.)-])\s+'), '')
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s+(?=[A-Za-z])'), '')
        .trim();
    if (_isAdministrativeLine(line)) return null;

    final matches = _amountPattern.allMatches(line).toList();
    if (matches.isEmpty) return null;
    final last = matches.last;
    if (line.substring(last.end).trim().length > 2) return null;

    var name = line.substring(0, matches.first.start).trim();
    name = name
        .replaceAll(RegExp(r'[-:*]+$'), '')
        .replaceAll(RegExp(r'\s+[xX]$'), '')
        .trim();
    if (!_isPlausibleProductName(name)) return null;

    final values = matches
        .map((match) => _toAmount(match.group(1)!))
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;

    final lineTotal = values.last.abs();
    final rawLineTotal = last.group(1)!.replaceAll(RegExp(r'[-,]'), '');
    final maximumFromBill = printedTotal == null
        ? 100000.0
        : (printedTotal * 1.5 < 100 ? 100.0 : printedTotal * 1.5);
    if (lineTotal <= 0 ||
        lineTotal > 100000 ||
        lineTotal > maximumFromBill ||
        (!rawLineTotal.contains('.') && rawLineTotal.length >= 6)) {
      return null;
    }

    var quantity = 1.0;
    var unitPrice = lineTotal;
    var confidence = 0.72;
    if (values.length >= 3) {
      final proposedQuantity = values[values.length - 3];
      final proposedUnitPrice = values[values.length - 2];
      final proposedTotal = proposedQuantity * proposedUnitPrice;
      final tolerance = (lineTotal * 0.04).clamp(0.10, 1.00);
      if (proposedQuantity > 0 &&
          proposedQuantity <= 100 &&
          proposedUnitPrice > 0 &&
          (proposedTotal - lineTotal).abs() <= tolerance) {
        quantity = proposedQuantity;
        unitPrice = proposedUnitPrice;
        confidence = 0.92;
      }
    } else if (values.length == 2 &&
        RegExp(r'\b\d+(?:\.\d+)?\s*[xX]\s*').hasMatch(line)) {
      final proposedQuantity = values.first;
      if (proposedQuantity > 0 && proposedQuantity <= 100) {
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

  bool _isItemHeader(String line) {
    final lower = line.toLowerCase();
    return RegExp(r'\b(it[ea][mn]s?|particulars?|description|products?)\b')
            .hasMatch(lower) &&
        !_isDiscountLine(lower);
  }

  bool _isSummaryStart(String lower) => RegExp(
        r'\b(sub\s*total|grand\s*total|net\s*(?:amount|total)|amount\s*payable|taxable\s*amount|payment\s*summary)\b',
      ).hasMatch(lower);

  bool _isAdministrativeLine(String line) =>
      _nonItemWords.hasMatch(line) ||
      _administrativeFragments.hasMatch(line) ||
      _longIdentifier.hasMatch(line);

  bool _isPossibleProductName(String line) =>
      !_amountPattern.hasMatch(line) &&
      !_datePattern.hasMatch(line) &&
      _isPlausibleProductName(line);

  bool _isPlausibleProductName(String name) {
    if (name.length < 3 || name.length > 80 || !_letters.hasMatch(name)) {
      return false;
    }
    final letterCount = _letters.allMatches(name).length;
    if (letterCount < 3 || _longIdentifier.hasMatch(name)) return false;
    final meaningfulCount = RegExp(r'[A-Za-z0-9]').allMatches(name).length;
    if (meaningfulCount == 0 || letterCount / meaningfulCount < 0.5) {
      return false;
    }
    if (RegExp(r'^\d').hasMatch(name) && letterCount < 4) return false;
    return true;
  }

  String _findStore(List<String> lines) {
    final headerIndex = lines.indexWhere(_isItemHeader);
    final candidates = lines.take(
      headerIndex > 0 && headerIndex < 12 ? headerIndex : 10,
    );
    String? best;
    var bestScore = -1;
    for (final line in candidates) {
      final lower = line.toLowerCase();
      if (line.length < 3 ||
          line.length > 48 ||
          !_letters.hasMatch(line) ||
          _amountPattern.hasMatch(line) ||
          _datePattern.hasMatch(line) ||
          RegExp(
            r'\b(invoice|receipt|tax|gstin|fssai|phone|mobile|address|cashier|date|time|bill|welcome|thank)\b',
            caseSensitive: false,
          ).hasMatch(lower) ||
          _administrativeFragments.hasMatch(lower) ||
          _longIdentifier.hasMatch(line)) {
        continue;
      }
      final letterCount = _letters.allMatches(line).length;
      final wordCount = line.split(' ').where((word) => word.isNotEmpty).length;
      var score = letterCount + (wordCount * 4);
      if (RegExp(
        r'\b(mart|market|supermarket|stores?|bazaar|basket|fresh|retail|hyper)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        score += 30;
      }
      if (score > bestScore) {
        best = line;
        bestScore = score;
      }
    }
    return best == null ? 'Scanned grocery bill' : _titleCase(best);
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
