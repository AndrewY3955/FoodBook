import 'package:cookistrybook/src/data/models/enums.dart';
import 'package:cookistrybook/src/data/models/food_item.dart';
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

  test('online foods fill in ingredients the built-in table lacks', () {
    final FoodItem goo = FoodItem.fromJson(<String, dynamic>{
      'id': 'fdc:1',
      'name': 'Mystery goo',
      'per100g': <String, dynamic>{'calories': 200, 'protein_g': 10},
      'servingGrams': 30,
    });
    final NutritionEstimate e = NutritionEstimator.estimate(
      <DraftIngredient>[
        DraftIngredient(
            ingredientId: '',
            name: 'mystery goo',
            quantity: 100,
            unit: MeasureUnit.g),
        DraftIngredient(
            ingredientId: '',
            name: 'mystery goo',
            quantity: 2,
            unit: MeasureUnit.piece),
      ],
      1,
      online: <String, FoodItem>{'mystery goo': goo},
    );
    expect(e.counted.length, 2);
    // 100 g + 2 x 30 g servings = 160 g at 200 kcal / 100 g.
    expect(e.nutrition.calories, 320);
    expect(goo.nutritionFor(50)['protein_g'], 5);
  });

  test('online foods require food-specific data for volume conversions', () {
    final FoodItem flour = FoodItem.fromJson(<String, dynamic>{
      'id': 'fdc:2',
      'name': 'Unknown flour',
      'per100g': <String, dynamic>{'calories': 364, 'carbs_g': 76},
      'servingGrams': 30,
    });

    expect(NutritionEstimator.gramsOnline(flour, 1, MeasureUnit.g), 1);
    expect(NutritionEstimator.gramsOnline(flour, 1, MeasureUnit.kg), 1000);
    expect(NutritionEstimator.gramsOnline(flour, 1, MeasureUnit.oz), 28.35);
    expect(NutritionEstimator.gramsOnline(flour, 1, MeasureUnit.lb), 453.6);

    // A serving weight does not establish the density of a cup, spoon,
    // or millilitre. Do not silently treat flour like water.
    for (final MeasureUnit unit in <MeasureUnit>[
      MeasureUnit.cup,
      MeasureUnit.tbsp,
      MeasureUnit.tsp,
      MeasureUnit.flOz,
      MeasureUnit.ml,
      MeasureUnit.l,
      MeasureUnit.pinch,
    ]) {
      expect(NutritionEstimator.gramsOnline(flour, 1, unit), isNull,
          reason: 'No food-specific volume conversion is available for $unit');
    }
  });

  test('applying an estimate preserves existing nutrition and fills gaps', () {
    const Nutrition entered = Nutrition(
      values: <String, double>{
        'calories': 777,
        'sodium_mg': 900,
      },
      servingSize: '1 bowl',
    );
    const Nutrition estimate = Nutrition(
      values: <String, double>{
        'calories': 500,
        'protein_g': 24,
        'sodium_mg': 300,
      },
      servingSize: '1 serving',
    );

    final Nutrition merged = entered.fillMissingFrom(estimate);

    expect(merged['calories'], 777);
    expect(merged['sodium_mg'], 900);
    expect(merged['protein_g'], 24);
    expect(merged.servingSize, '1 bowl');
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
