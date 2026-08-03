import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import 'backup_service.dart';

class ReceiptExport {
  static String _cell(Object? value) =>
      '"${value.toString().replaceAll('"', '""')}"';

  Future<void> shareCsv(Receipt receipt) async {
    final rows = <String>[
      'Store,Date,Item,Category,Quantity,Unit Price,Discount,Line Total,Confidence',
      ...receipt.items.map((item) => [
            receipt.store,
            receipt.purchasedAt.toIso8601String(),
            item.name,
            item.category,
            item.quantity,
            item.unitPrice.toStringAsFixed(2),
            item.discount.toStringAsFixed(2),
            item.total.toStringAsFixed(2),
            item.confidence.toStringAsFixed(2),
          ].map(_cell).join(',')),
      '',
      'Printed Total,${receipt.printedTotal.toStringAsFixed(2)}',
      'Calculated Total,${receipt.calculatedTotal.toStringAsFixed(2)}',
      'Difference,${receipt.difference.toStringAsFixed(2)}',
    ];
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CartSense_${receipt.id}.csv');
    await file.writeAsString(rows.join('\n'));
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      text: 'CartSense itemised grocery bill',
    );
  }

  Future<void> shareInsightsReport(List<Receipt> receipts) async {
    final file = await writeInsightsCsv(receipts);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      text: 'CartSense grocery report',
    );
  }

  Future<File> writeInsightsCsv(List<Receipt> receipts) async {
    final safeReceipts = [...receipts]
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    final rows = <String>[
      'CartSense Grocery Report',
      'Generated,${DateTime.now().toIso8601String()}',
      '',
      'Summary',
      'Saved Bills,${safeReceipts.length}',
      'Total Spend,${_money(_sumReceipts(safeReceipts))}',
      'Stores,${_uniqueStores(safeReceipts)}',
      'Products,${safeReceipts.fold<int>(0, (count, receipt) => count + receipt.items.length)}',
      '',
      'Bills',
      'Date,Store,Printed Total,Calculated Total,Products',
      ...safeReceipts.map((receipt) => [
            receipt.purchasedAt.toIso8601String(),
            receipt.store,
            receipt.printedTotal.toStringAsFixed(2),
            receipt.calculatedTotal.toStringAsFixed(2),
            receipt.items.length,
          ].map(_cell).join(',')),
      '',
      'Category Spend',
      'Category,Amount',
      ..._categoryTotals(safeReceipts).entries.map(
            (entry) => [_cell(entry.key), _cell(entry.value.toStringAsFixed(2))]
                .join(','),
          ),
      '',
      'Store Spend',
      'Store,Bills,Amount',
      ..._storeTotals(safeReceipts).map(
        (entry) => [
          entry.name,
          entry.billCount,
          entry.total.toStringAsFixed(2),
        ].map(_cell).join(','),
      ),
      '',
      'Top Products',
      'Product,Category,Quantity,Amount',
      ..._productTotals(safeReceipts).take(30).map(
            (entry) => [
              entry.name,
              entry.category,
              entry.quantity.toStringAsFixed(2),
              entry.total.toStringAsFixed(2),
            ].map(_cell).join(','),
          ),
    ];
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CartSense_Grocery_Report.csv');
    await file.writeAsString(rows.join('\n'));
    return file;
  }

  Future<void> shareMonthlyPdfReport(List<Receipt> receipts) async {
    final file = await writeMonthlyPdfReport(receipts);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'CartSense monthly grocery report',
    );
  }

  Future<File> writeMonthlyPdfReport(List<Receipt> receipts) async {
    final now = DateTime.now();
    final currentMonth = receipts
        .where((receipt) =>
            receipt.purchasedAt.year == now.year &&
            receipt.purchasedAt.month == now.month)
        .toList();
    final source = currentMonth.isEmpty ? receipts : currentMonth;
    final categories = _categoryTotals(source);
    final stores = _storeTotals(source);
    final products = _productTotals(source);
    final lines = <String>[
      'CartSense Monthly Grocery Report',
      currentMonth.isEmpty
          ? 'Showing all saved bills because this month has no saved bills.'
          : '${_monthName(now.month)} ${now.year}',
      '',
      'Saved bills: ${source.length}',
      'Total spend: Rs ${_money(_sumReceipts(source))}',
      'Stores: ${_uniqueStores(source)}',
      '',
      'Category spend',
      ...categories.entries
          .take(12)
          .map((entry) => '${entry.key}: Rs ${_money(entry.value)}'),
      '',
      'Top stores',
      ...stores
          .take(8)
          .map((entry) => '${entry.name}: Rs ${_money(entry.total)}'),
      '',
      'Top products',
      ...products.take(12).map(
            (entry) => '${entry.name}: Rs ${_money(entry.total)}',
          ),
    ];
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CartSense_Monthly_Report.pdf');
    await file.writeAsBytes(_simplePdf(lines));
    return file;
  }

  Future<void> shareWhatsAppSummary(List<Receipt> receipts) async {
    await Share.share(
      whatsappSummary(receipts),
      subject: 'CartSense grocery summary',
    );
  }

  String whatsappSummary(List<Receipt> receipts) {
    final now = DateTime.now();
    final currentMonth = receipts
        .where((receipt) =>
            receipt.purchasedAt.year == now.year &&
            receipt.purchasedAt.month == now.month)
        .toList();
    final source = currentMonth.isEmpty ? receipts : currentMonth;
    final categories = _categoryTotals(source).entries.take(5).toList();
    final stores = _storeTotals(source).take(3).toList();
    return [
      'CartSense grocery summary',
      currentMonth.isEmpty
          ? 'All saved bills'
          : '${_monthName(now.month)} ${now.year}',
      '',
      'Bills: ${source.length}',
      'Spend: Rs ${_money(_sumReceipts(source))}',
      if (categories.isNotEmpty) '',
      if (categories.isNotEmpty) 'Top categories:',
      ...categories.map((entry) => '- ${entry.key}: Rs ${_money(entry.value)}'),
      if (stores.isNotEmpty) '',
      if (stores.isNotEmpty) 'Top stores:',
      ...stores.map((entry) => '- ${entry.name}: Rs ${_money(entry.total)}'),
      '',
      'Shared from CartSense',
    ].join('\n');
  }

  Future<void> shareCategoryChart(List<Receipt> receipts) async {
    final file = await writeCategoryChart(receipts);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/svg+xml')],
      text: 'CartSense category spending chart',
    );
  }

  Future<File> writeCategoryChart(List<Receipt> receipts) async {
    final categories = _categoryTotals(receipts).entries.take(8).toList();
    final maximum = categories.fold(
      0.0,
      (max, entry) => entry.value > max ? entry.value : max,
    );
    final height = 120 + categories.length * 48;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="$height" viewBox="0 0 900 $height">',
      )
      ..writeln('<rect width="900" height="$height" fill="#F6F7F3"/>')
      ..writeln(
        '<text x="40" y="52" font-family="Arial" font-size="32" font-weight="700" fill="#145A43">CartSense category spend</text>',
      );
    for (var index = 0; index < categories.length; index++) {
      final entry = categories[index];
      final y = 96 + index * 48;
      final width = maximum <= 0 ? 0 : (entry.value / maximum) * 520;
      buffer
        ..writeln(
          '<text x="40" y="${y + 24}" font-family="Arial" font-size="22" fill="#17221D">${_xml(entry.key)}</text>',
        )
        ..writeln(
          '<rect x="260" y="$y" width="$width" height="28" rx="14" fill="#145A43"/>',
        )
        ..writeln(
          '<text x="${280 + width}" y="${y + 22}" font-family="Arial" font-size="20" font-weight="700" fill="#17221D">Rs ${_money(entry.value)}</text>',
        );
    }
    buffer.writeln('</svg>');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CartSense_Category_Chart.svg');
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<void> shareFullExportBundle(List<Receipt> receipts) async {
    final csv = await writeInsightsCsv(receipts);
    final pdf = await writeMonthlyPdfReport(receipts);
    final chart = await writeCategoryChart(receipts);
    final backup = await CartSenseBackupService().writeBackupFile();
    await Share.shareXFiles(
      [
        XFile(csv.path, mimeType: 'text/csv'),
        XFile(pdf.path, mimeType: 'application/pdf'),
        XFile(chart.path, mimeType: 'image/svg+xml'),
        XFile(backup.path, mimeType: 'application/json'),
      ],
      text: 'CartSense reports and backup',
    );
  }

  static double _sumReceipts(List<Receipt> receipts) => receipts.fold(
        0,
        (sum, receipt) => sum + receipt.calculatedTotal,
      );

  static String _money(double value) => value.toStringAsFixed(2);

  static int _uniqueStores(List<Receipt> receipts) => receipts
      .map((receipt) =>
          receipt.store.trim().isEmpty ? 'Unknown store' : receipt.store.trim())
      .toSet()
      .length;

  static Map<String, double> _categoryTotals(List<Receipt> receipts) {
    final totals = <String, double>{};
    for (final receipt in receipts) {
      for (final item in receipt.items) {
        final category =
            item.category.trim().isEmpty ? 'Other' : item.category.trim();
        totals[category] = (totals[category] ?? 0) + item.total;
      }
    }
    return Map.fromEntries(
      totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  static List<_StoreTotal> _storeTotals(List<Receipt> receipts) {
    final totals = <String, _StoreTotal>{};
    for (final receipt in receipts) {
      final name =
          receipt.store.trim().isEmpty ? 'Unknown store' : receipt.store.trim();
      final current = totals[name] ?? _StoreTotal(name, 0, 0);
      totals[name] = _StoreTotal(
        name,
        current.total + receipt.calculatedTotal,
        current.billCount + 1,
      );
    }
    return totals.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  static List<_ProductTotal> _productTotals(List<Receipt> receipts) {
    final totals = <String, _ProductTotal>{};
    for (final receipt in receipts) {
      for (final item in receipt.items) {
        final key = normalizedProductName(item.name);
        if (key.length < 2) continue;
        final current =
            totals[key] ?? _ProductTotal(item.name, item.category, 0, 0);
        totals[key] = _ProductTotal(
          item.name,
          item.category,
          current.quantity + item.quantity,
          current.total + item.total,
        );
      }
    }
    return totals.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }
}

String _monthName(int month) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _pdfText(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('(', r'\(')
    .replaceAll(')', r'\)')
    .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');

List<int> _simplePdf(List<String> lines) {
  final objects = <String>[];
  var content = StringBuffer()
    ..writeln('BT')
    ..writeln('/F1 18 Tf')
    ..writeln('72 770 Td');
  for (var index = 0; index < lines.length && index < 42; index++) {
    final size = index == 0 ? 20 : 11;
    content
      ..writeln('/F1 $size Tf')
      ..writeln('(${_pdfText(lines[index])}) Tj')
      ..writeln('0 -18 Td');
  }
  content.writeln('ET');
  final stream = content.toString();
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  objects.add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  objects.add(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
  );
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  var byteCount = buffer.toString().codeUnits.length;
  for (var i = 0; i < objects.length; i++) {
    offsets.add(byteCount);
    final object = '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
    buffer.write(object);
    byteCount += object.codeUnits.length;
  }
  final xrefStart = byteCount;
  buffer
    ..writeln('xref')
    ..writeln('0 ${objects.length + 1}')
    ..writeln('0000000000 65535 f ');
  for (final offset in offsets.skip(1)) {
    buffer.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer
    ..writeln('trailer')
    ..writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>')
    ..writeln('startxref')
    ..writeln('$xrefStart')
    ..writeln('%%EOF');
  return buffer.toString().codeUnits;
}

class _StoreTotal {
  const _StoreTotal(this.name, this.total, this.billCount);

  final String name;
  final double total;
  final int billCount;
}

class _ProductTotal {
  const _ProductTotal(this.name, this.category, this.quantity, this.total);

  final String name;
  final String category;
  final double quantity;
  final double total;
}
