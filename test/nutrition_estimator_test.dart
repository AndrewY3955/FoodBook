import 'package:cookistrybook/src/data/models/enums.dart';
import 'package:cookistrybook/src/data/models/models.dart';
import 'package:cookistrybook/src/data/nutrition_estimator.dart';
import 'package:cookistrybook/src/data/repositories/nutrition_repository.dart';
import 'package:cookistrybook/src/data/repositories/recipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimator fills macros and micros per serving', () {
    final NutritionEstimate e = NutritionEstimator.estimate(<DraftIngredient>[
      DraftIngredient(
          ingredientId: "",
          name: 'whole milk',
          quantity: 2,
          unit: MeasureUnit.cup),
      DraftIngredient(
          ingredientId: "",
          name: 'mystery goo',
          quantity: 1,
          unit: MeasureUnit.cup),
    ], 2);
    expect(e.counted.length, 1);
    expect(e.skipped, contains('mystery goo'));
    expect(e.nutrition.calories, greaterThan(100));
    expect(e.nutrition['protein_g'], greaterThan(5));
    expect(e.nutrition['calcium_mg'], greaterThan(100));
  });

  test('micros survive a json round trip', () {
    final Nutrition n = const Nutrition().withValue('zinc_mg', 3.5);
    final Nutrition back = Nutrition.fromJson(n.toJson());
    expect(back['zinc_mg'], 3.5);
  });

  test('goals split calories into macro grams', () {
    final NutritionGoals g = NutritionGoals.fromSplit(
        calories: 2000, carbsPct: 50, proteinPct: 20, fatPct: 30);
    expect(g.carbsG, 250);
    expect(g.proteinG, 100);
    expect(g.fatG.round(), 67);
  });
}

