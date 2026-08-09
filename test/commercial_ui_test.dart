import 'package:cartsense_lite/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch shows the CartSense onboarding guide',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Scan grocery bills'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Scan a grocery receipt'), findsOneWidget);
  });

  testWidgets('home presents a focused commercial navigation hierarchy',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
      'cartsense_family_profile_prompted_v1': true,
    });

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
    expect(find.text('Scan first receipt'), findsOneWidget);
    expect(find.text('Plan list'), findsOneWidget);
    expect(find.text('Try demo'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('CartSense data'), findsOneWidget);
    expect(find.text('Backup and restore'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Product memory'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Product memory'), findsOneWidget);
  });

  testWidgets('footer navigation stays available on main workflow screens',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
      'cartsense_family_profile_prompted_v1': true,
    });

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();

    expect(find.text('Shopping Assistant'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Insights'), findsWidgets);

    await tester.tap(find.text('Insights').last);
    await tester.pumpAndSettle();

    expect(find.text('Insights'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Saved bills'), findsOneWidget);
    expect(find.text('Export grocery report'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Store comparison'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Store comparison'), findsOneWidget);
  });

  testWidgets('existing users see family profile onboarding once if missing',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
    });

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Scan grocery bills'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Set up your household'), findsOneWidget);

    await tester.tap(find.text('Start using CartSense'));
    await tester.pumpAndSettle();

    expect(find.text('Scan a grocery receipt'), findsOneWidget);
  });
}
