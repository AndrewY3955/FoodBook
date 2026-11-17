import 'package:flutter_test/flutter_test.dart';
import 'package:cookistrybook/src/data/nutrition_db.dart';
import 'package:cookistrybook/src/data/nutrition_micros.dart';

void main() {
  test('built-in food reference weights and nutrient values are valid', () {
    for (final Food food in kFoods) {
      expect(food.names.trim(), isNotEmpty, reason: 'Food names are required');
      expect(
        food.names.split('|').every((String name) => name.trim().isNotEmpty),
        isTrue,
        reason: 'Food aliases must not be empty: ${food.names}',
      );
      for (final double value in <double>[
        food.kcal,
        food.protein,
        food.carbs,
        food.fat,
        food.fiber,
        food.sugar,
        food.satFat,
        food.sodium,
        food.cholesterol,
        food.potassium,
        food.calcium,
        food.iron,
        food.vitC,
      ]) {
        expect(value, isFinite, reason: food.names);
        expect(value, greaterThanOrEqualTo(0), reason: food.names);
      }
      expect(food.protein, greaterThanOrEqualTo(0), reason: food.names);
      expect(food.carbs, greaterThanOrEqualTo(0), reason: food.names);
      expect(food.fat, greaterThanOrEqualTo(0), reason: food.names);
      if (food.gramsPerCup != null) {
        expect(food.gramsPerCup, greaterThan(0), reason: food.names);
      }
      if (food.gramsEach != null) {
        expect(food.gramsEach, greaterThan(0), reason: food.names);
      }
    }
  });

  test('micronutrient rows align with the food database and nutrient order', () {
    final Set<String> foodKeys = kFoods
        .map((Food food) => food.names.split('|').first)
        .toSet();

    for (final MapEntry<String, List<double>> entry
        in kFoodMicros.entries) {
      expect(foodKeys, contains(entry.key), reason: entry.key);
      expect(entry.value, hasLength(kMicroOrder.length),
          reason: 'Values must follow kMicroOrder for ${entry.key}');
      for (final double value in entry.value) {
        expect(value, isFinite, reason: entry.key);
        expect(value, greaterThanOrEqualTo(0), reason: entry.key);
      }
    }
  });
}
