import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/receipt.dart';

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
}
