import 'package:cookistrybook/src/ui/widgets/maintenance_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calculates and uses an estimate without submitting data',
      (WidgetTester tester) async {
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

    expect(find.text('About 2200 calories a day'), findsOneWidget);
    await tester.tap(find.text('Use estimate'));
    expect(usedEstimate, 2200);
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
    expect(find.text('Use estimate'), findsNothing);
    expect(find.text('Save my details'), findsNothing);
    expect(find.text('Log weight'), findsNothing);
  });
}
