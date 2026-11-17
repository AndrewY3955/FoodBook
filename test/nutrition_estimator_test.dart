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

  test('online serving weights are not treated as individual-piece weights', () {
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
            name: 'mystery goo pieces',
            quantity: 2,
            unit: MeasureUnit.piece),
      ],
      1,
      online: <String, FoodItem>{
        'mystery goo': goo,
        'mystery goo pieces': goo,
      },
    );

    // Only the explicit 100 g amount is counted. The 30 g labelled serving
    // does not tell us the weight of each individual piece.
    expect(e.counted, <String>['mystery goo']);
    expect(e.skipped, <String>['mystery goo pieces']);
    expect(e.skippedReasons['mystery goo pieces'], contains('conversion'));
    expect(e.nutrition.calories, 200);
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
      MeasureUnit.unit,
      MeasureUnit.piece,
      MeasureUnit.clove,
      MeasureUnit.slice,
    ]) {
      expect(NutritionEstimator.gramsOnline(flour, 1, unit), isNull,
          reason: 'A labelled serving is not an individual-item weight for $unit');
    }
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

  test('explains why unmatched online ingredients are skipped', () {
    final NutritionEstimate estimate = NutritionEstimator.estimate(
      <DraftIngredient>[
        DraftIngredient(
          ingredientId: '',
          name: 'unknown flour',
          quantity: 1,
          unit: MeasureUnit.cup,
        ),
        DraftIngredient(
          ingredientId: '',
          name: 'unlisted food',
          quantity: 2,
          unit: MeasureUnit.g,
        ),
        DraftIngredient(
          ingredientId: '',
          name: 'whole milk',
          quantity: 0,
          unit: MeasureUnit.cup,
        ),
      ],
      1,
      online: <String, FoodItem>{
        'unknown flour': FoodItem.fromJson(<String, dynamic>{
          'id': 'fdc:3',
          'name': 'Unknown flour',
          'per100g': <String, dynamic>{'calories': 364},
        }),
      },
    );

    expect(estimate.skipped, containsAll(<String>[
      'unknown flour',
      'unlisted food',
      'whole milk',
    ]));
    expect(estimate.skippedReasons['unknown flour'], contains('conversion'));
    expect(estimate.skippedReasons['unlisted food'], contains('No matching'));
    expect(estimate.skippedReasons['whole milk'], contains('greater than zero'));
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

  test('explicit preparation state never falls back to a different food form', () {
    expect(NutritionEstimator.match('cooked rice')?.names, contains('cooked rice'));
    expect(NutritionEstimator.match('raw rice')?.names, contains('white rice'));
    expect(NutritionEstimator.match('cooked chicken breast'), isNull);
    expect(NutritionEstimator.match('grilled chicken breast'), isNull);
    expect(NutritionEstimator.match('canned black beans'), isNull);
    expect(NutritionEstimator.match('raw chicken breast')?.names,
        contains('chicken breast'));
    // Dry-weight references must not be used for unqualified cooked staples.
    expect(NutritionEstimator.match('rice'), isNull);
    expect(NutritionEstimator.match('white rice'), isNull);
    expect(NutritionEstimator.match('black beans'), isNull);
    expect(NutritionEstimator.match('chickpeas'), isNull);
    expect(NutritionEstimator.match('lentils'), isNull);
    expect(NutritionEstimator.match('pasta'), isNull);
    expect(NutritionEstimator.match('dry white rice')?.names,
        contains('white rice'));
    expect(NutritionEstimator.match('dry black beans')?.names,
        contains('black beans'));
  });

  test('unreported micronutrients are omitted instead of treated as zero', () {
    final NutritionEstimate estimate = NutritionEstimator.estimate(
      <DraftIngredient>[
        DraftIngredient(ingredientId: '', name: 'water', quantity: 100,
            unit: MeasureUnit.g),
        DraftIngredient(ingredientId: '', name: 'broccoli', quantity: 100,
            unit: MeasureUnit.g),
      ],
      1,
    );
    // Water has no micronutrient record. Broccoli's values alone would
    // understate the recipe total, so the combined total is not displayed.
    expect(estimate.nutrition['vitamin_c_mg'], isNull);
    expect(estimate.nutrition['protein_g'], isNotNull);
    expect(estimate.nutrition['calories'], isNotNull);
  });

  test('online nutrient totals omit fields missing from any selected food', () {
    FoodItem food(String id, Map<String, double> values) =>
        FoodItem(id: id, name: id, per100g: Nutrition(values: values));
    final NutritionEstimate estimate = NutritionEstimator.estimate(
      <DraftIngredient>[
        DraftIngredient(ingredientId: '', name: 'online alpha', quantity: 100,
            unit: MeasureUnit.g),
        DraftIngredient(ingredientId: '', name: 'online beta', quantity: 100,
            unit: MeasureUnit.g),
      ],
      1,
      online: <String, FoodItem>{
        'online alpha': food('alpha', <String, double>{
          'calories': 100, 'protein_g': 10, 'sodium_mg': 50,
        }),
        'online beta': food('beta', <String, double>{
          'calories': 200, 'protein_g': 20,
        }),
      },
    );
    expect(estimate.nutrition['calories'], 300);
    expect(estimate.nutrition['protein_g'], 30);
    expect(estimate.nutrition['sodium_mg'], isNull);
  });

  test('reports nutrient fields omitted because ingredient data is incomplete', () {
    final NutritionEstimate estimate = NutritionEstimator.estimate(
      <DraftIngredient>[
        DraftIngredient(ingredientId: '', name: 'water', quantity: 100,
            unit: MeasureUnit.g),
      ],
      1,
    );
    expect(estimate.incompleteNutrients, contains('vitamin_c_mg'));
    expect(estimate.nutrition['vitamin_c_mg'], isNull);
  });
}
