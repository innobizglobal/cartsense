import 'package:cartsense_lite/main.dart';
import 'package:cartsense_lite/screens/shopping_list_screen.dart';
import 'package:cartsense_lite/widgets/app_footer_nav.dart';
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

    expect(find.text('Scan your bill'), findsOneWidget);
  });

  testWidgets('home presents a focused commercial navigation hierarchy',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
      'cartsense_family_profile_prompted_v1': true,
      'cartsense_guided_tour_acknowledged_v2': true,
    });

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('CartSense'), findsOneWidget);
    expect(find.text('Scan your bill'), findsOneWidget);
    expect(find.text('Scan now'), findsOneWidget);
    expect(find.byType(CartSenseFooterNav), findsOneWidget);
    expect(find.text('AI + PRIVATE'), findsNothing);
    expect(find.text('Try a complete demo bill'), findsNothing);

    expect(find.byType(CartSenseFooterNav), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Spend'), findsOneWidget);

    await tester.tap(find.text('Bills').last);
    await tester.pumpAndSettle();
    expect(find.text('My Bills'), findsWidgets);
    expect(find.text('Your shopping record'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No bills saved yet'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No bills saved yet'), findsOneWidget);
    expect(find.text('Scan bill'), findsOneWidget);
    expect(find.text('Plan list'), findsNothing);
    expect(find.text('Try demo'), findsNothing);

    Navigator.of(tester.element(find.text('My Bills').first)).pop();
    await tester.pumpAndSettle();

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
      'cartsense_guided_tour_acknowledged_v2': true,
    });

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shopping').first);
    await tester.pumpAndSettle();

    expect(find.text('Shopping Assistant'), findsWidgets);
    expect(find.byType(CartSenseFooterNav), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Shopping'), findsWidgets);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Spend'), findsOneWidget);

    await tester.tap(find.text('Spend').last);
    await tester.pumpAndSettle();

    expect(find.text('Insights'), findsWidgets);
    expect(find.byType(CartSenseFooterNav), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Spend'), findsWidgets);
    expect(find.text('Saved bills'), findsOneWidget);
    expect(find.text('Export grocery report'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Store comparison'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Store comparison'), findsOneWidget);
  });

  testWidgets('shopping assistant adds pasted grocery items immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
      'cartsense_family_profile_prompted_v1': true,
      'cartsense_guided_tour_acknowledged_v2': true,
    });

    await tester.pumpWidget(const MaterialApp(
      home: ShoppingListScreen(receipts: []),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shopping_items_input')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byTooltip('Speak shopping list'), findsOneWidget);
    expect(find.text('You can type or speak your list.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('shopping_items_input')),
      'tea 1, coffee 2',
    );
    await tester.pump();
    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Add to list'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add to list'));
    await tester.pumpAndSettle();

    expect(find.text('2 products added to your list.'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('tea'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('tea'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('coffee'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('coffee'), findsWidgets);
  });

  testWidgets('home greets the configured user by name', (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
      'cartsense_family_profile_prompted_v1': true,
      'cartsense_guided_tour_acknowledged_v2': true,
      'cartsense_user_name_v1': 'Lakshmi',
    });

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Hi Lakshmi'), findsWidgets);
    expect(
      find.text('Let’s make shopping easier today.'),
      findsOneWidget,
    );
  });

  testWidgets('guided tour remains until user skips or completes it',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartsense_onboarding_complete': true,
      'cartsense_family_profile_prompted_v1': true,
    });

    await tester.pumpWidget(const CartSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Scan grocery bills'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Scan your bill'), findsOneWidget);
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

    expect(find.text('Scan your bill'), findsOneWidget);
  });
}
