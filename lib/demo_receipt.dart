import 'models/receipt.dart';

Receipt createDemoReceipt() => Receipt(
      id: 'DEMO-${DateTime.now().millisecondsSinceEpoch}',
      store: 'DMart – Hyderabad',
      purchasedAt: DateTime.now(),
      printedTotal: 1488.50,
      items: [
        ReceiptItem(
            name: 'India Gate Basmati Rice 5 kg',
            quantity: 1,
            unitPrice: 699,
            discount: 50,
            confidence: .97),
        ReceiptItem(
            name: 'Fortune Sunflower Oil 1 L',
            quantity: 2,
            unitPrice: 132,
            discount: 18,
            confidence: .94),
        ReceiptItem(
            name: 'Aashirvaad Atta 5 kg',
            quantity: 1,
            unitPrice: 278,
            discount: 20,
            confidence: .92),
        ReceiptItem(
            name: 'Tata Salt 1 kg',
            quantity: 1,
            unitPrice: 27,
            discount: 0,
            confidence: .98),
        ReceiptItem(
            name: 'Amul Taaza Milk 1 L',
            quantity: 2,
            unitPrice: 69,
            discount: 0,
            confidence: .72),
        ReceiptItem(
            name: 'Surf Excel Easy Wash 1 kg',
            quantity: 1,
            unitPrice: 170.50,
            discount: 0,
            confidence: .68),
      ],
    );
