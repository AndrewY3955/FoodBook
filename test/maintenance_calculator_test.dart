import 'package:cookistrybook/src/ui/widgets/maintenance_calculator.dart';
import 'package:cookistrybook/src/data/energy_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calculates and uses an estimate without submitting data',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? usedEstimate;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MaintenanceCalculator(
          onUse: (int estimate) => usedEstimate = estimate,
        ),
      ),
    ));

    await tester.tap(find.text('Maintenance calories'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Age')), '20');
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Weight')), '190');
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Height')), '5');
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Inches')), '6');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<ActivityLevel>));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('Lightly active — Light exercise 1-3 days/week'));
    await tester.pumpAndSettle();

    expect(find.text('BMR: 1815 calories/day'), findsOneWidget);
    expect(find.text('TDEE: 2495 calories/day'), findsOneWidget);
    expect(
        find.text('Daily calorie target: 2495 calories/day'), findsOneWidget);
    await tester.tap(find.text('Use calorie target'));
    expect(usedEstimate, 2495);

    await tester.tap(find.text('Lose'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Weekly loss')), '1');
    await tester.pumpAndSettle();

    expect(
        find.text('Daily calorie target: 1996 calories/day'), findsOneWidget);
    await tester.tap(find.text('Use calorie target'));
    expect(usedEstimate, 1996);
  });

  testWidgets('asks for measurements instead of rejecting an empty form',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MaintenanceCalculator(onUse: (_) {}),
      ),
    ));

    await tester.tap(find.text('Maintenance calories'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your age, weight, and height to see an estimate.'),
      findsOneWidget,
    );
    expect(find.text('Use calorie target'), findsNothing);
    expect(find.text('Save my details'), findsNothing);
    expect(find.text('Log weight'), findsNothing);
  });

  testWidgets('requires a weekly amount before applying loss or gain',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MaintenanceCalculator(onUse: (_) {}),
      ),
    ));

    await tester.tap(find.text('Maintenance calories'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Age')), '30');
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Weight')), '180');
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Height')), '5');
    await tester.enterText(
        find.byKey(const ValueKey<String>('maintenance-Inches')), '10');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gain'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter your weekly gain'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
