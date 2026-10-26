// Run: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:cookistrybook/src/core/quantity_format.dart';
import 'package:cookistrybook/src/data/models/enums.dart';
import 'package:cookistrybook/src/data/models/models.dart';
import 'package:cookistrybook/src/state/portion_scaler.dart';
import 'package:cookistrybook/src/ui/responsive/breakpoints.dart';

RecipeIngredient line(
  double quantity,
  MeasureUnit unit, {
  String name = 'Thing',
}) =>
    RecipeIngredient(
      id: 'i',
      ingredientId: 'g',
      name: name,
      quantity: quantity,
      unit: unit,
      category: GroceryCategory.other,
    );

void main() {
  group('factor', () {
    test('doubling', () {
      expect(PortionScaler.factor(baseServings: 2, targetServings: 4), 2.0);
    });

    test('halving', () {
      expect(PortionScaler.factor(baseServings: 4, targetServings: 2), 0.5);
    });

    test('guards against a zero base', () {
      expect(PortionScaler.factor(baseServings: 0, targetServings: 4), 1.0);
    });

    test('clamps the target to the column bounds', () {
      expect(PortionScaler.clampServings(0), 1);
      expect(PortionScaler.clampServings(500), 100);
    });
  });

  group('scaleLine', () {
    test('scales an ordinary quantity', () {
      expect(PortionScaler.scaleLine(line(2, MeasureUnit.tbsp), 2).quantity, 4);
    });

    test('never scales "to taste"', () {
      final RecipeIngredient scaled =
          PortionScaler.scaleLine(line(1, MeasureUnit.toTaste), 8);
      expect(scaled.quantity, 1);
    });

    test('rounds to three decimals to match numeric(10,3)', () {
      final RecipeIngredient scaled =
          PortionScaler.scaleLine(line(1, MeasureUnit.cup), 1 / 3);
      expect(scaled.quantity, 0.333);
    });

    test('is a no-op at factor 1', () {
      final RecipeIngredient original = line(2.5, MeasureUnit.cup);
      expect(PortionScaler.scaleLine(original, 1).quantity, 2.5);
    });
  });

  group('QuantityFormat', () {
    test('renders common library fractions', () {
      expect(QuantityFormat.amount(0.5), '1/2');
      expect(QuantityFormat.amount(0.25), '1/4');
      expect(QuantityFormat.amount(1.5), '1 1/2');
      expect(QuantityFormat.amount(0.333), '1/3');
    });

    test('renders whole numbers without decoration', () {
      expect(QuantityFormat.amount(2), '2');
      expect(QuantityFormat.amount(2.0), '2');
    });

    test('pluralises only the units that take it', () {
      expect(QuantityFormat.withUnit(2, MeasureUnit.clove), '2 cloves');
      expect(QuantityFormat.withUnit(1, MeasureUnit.clove), '1 clove');
      expect(QuantityFormat.withUnit(2, MeasureUnit.g), '2 g');
    });

    test('renders "to taste" as words, not a number', () {
      expect(QuantityFormat.withUnit(1, MeasureUnit.toTaste), 'to taste');
    });

    test('formats durations', () {
      expect(QuantityFormat.minutes(45), '45 min');
      expect(QuantityFormat.minutes(60), '1 h');
      expect(QuantityFormat.minutes(85), '1 h 25 min');
    });
  });

  group('Breakpoints', () {
    test('classifies by width', () {
      expect(Breakpoints.of(400), FormFactor.phone);
      expect(Breakpoints.of(599), FormFactor.phone);
      expect(Breakpoints.of(600), FormFactor.tablet);
      expect(Breakpoints.of(1023), FormFactor.tablet);
      expect(Breakpoints.of(1024), FormFactor.desktop);
    });

    test('scales the recipe grid with available width', () {
      expect(Breakpoints.recipeColumns(400), 1);
      expect(Breakpoints.recipeColumns(700), 2);
      expect(Breakpoints.recipeColumns(1000), 3);
      expect(Breakpoints.recipeColumns(1300), 4);
      expect(Breakpoints.recipeColumns(1700), 5);
    });

    test('splits the cooking pane only where two columns fit', () {
      expect(Breakpoints.splitCookingPane(700), isFalse);
      expect(Breakpoints.splitCookingPane(840), isTrue);
    });
  });
}
