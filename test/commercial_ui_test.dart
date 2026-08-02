import 'package:cartsense_lite/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home presents a focused commercial navigation hierarchy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('CartSense'), findsOneWidget);
    expect(find.text('Scan a grocery receipt'), findsOneWidget);
    expect(find.text('Scan receipt'), findsOneWidget);
    expect(find.text('Your shortcuts'), findsOneWidget);
    expect(find.text('AI + PRIVATE'), findsNothing);
    expect(find.text('Try a complete demo bill'), findsNothing);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Insights'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('No receipts yet'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent receipts'), findsOneWidget);
    expect(find.text('No receipts yet'), findsOneWidget);
  });
}
