import 'models/enums.dart';
import 'models/nutrition.dart';
import 'nutrition_db.dart';
import 'nutrition_micros.dart';
import 'repositories/recipe_repository.dart';

class NutritionEstimate {
  const NutritionEstimate({
    required this.nutrition,
    required this.counted,
    required this.skipped,
  });

  /// Per serving.
  final Nutrition nutrition;
  final List<String> counted;

  /// Ingredients that could not be matched or converted to a weight.
  final List<String> skipped;
}

class NutritionEstimator {
  const NutritionEstimator._();

  static final Map<Food, List<RegExp>> _patterns = <Food, List<RegExp>>{
    for (final Food f in kFoods)
      f: <RegExp>[
        for (final String n in f.names.split('|'))
          RegExp('(^|[^a-z])${RegExp.escape(n)}(s|es)?(\$|[^a-z])'),
      ],
  };

  /// Best database match for [name]: the longest matching phrase wins.
  static Food? match(String name) {
    final String n = name.toLowerCase().replaceAll(RegExp(r'[^a-z\- ]'), ' ');
    Food? best;
    int bestLen = 0;
    for (final MapEntry<Food, List<RegExp>> e in _patterns.entries) {
      final List<String> phrases = e.key.names.split('|');
      for (int i = 0; i < phrases.length; i++) {
        if (phrases[i].length > bestLen && e.value[i].hasMatch(n)) {
          best = e.key;
          bestLen = phrases[i].length;
        }
      }
    }
    return best;
  }

  /// Grams for [qty] of [unit] of [food], or null when it cannot be known.
  static double? grams(Food food, double qty, MeasureUnit unit) {
    final double? cup = food.gramsPerCup;
    switch (unit) {
      case MeasureUnit.g:
        return qty;
      case MeasureUnit.kg:
        return qty * 1000;
      case MeasureUnit.oz:
        return qty * 28.35;
      case MeasureUnit.lb:
        return qty * 453.6;
      case MeasureUnit.cup:
        return cup == null ? null : qty * cup;
      case MeasureUnit.tbsp:
        return cup == null ? null : qty * cup / 16;
      case MeasureUnit.tsp:
        return cup == null ? null : qty * cup / 48;
      case MeasureUnit.flOz:
        return cup == null ? null : qty * cup / 8;
      case MeasureUnit.ml:
        return cup == null ? null : qty * cup / 236.6;
      case MeasureUnit.l:
        return cup == null ? null : qty * cup * 1000 / 236.6;
      case MeasureUnit.pinch:
        return cup == null ? null : qty * cup / 800;
      case MeasureUnit.unit:
      case MeasureUnit.piece:
      case MeasureUnit.clove:
      case MeasureUnit.slice:
        return food.gramsEach == null ? null : qty * food.gramsEach!;
      case MeasureUnit.bunch:
      case MeasureUnit.can:
      case MeasureUnit.package:
      case MeasureUnit.toTaste:
        return null;
    }
  }

  static NutritionEstimate estimate(
    List<DraftIngredient> items,
    int servings,
  ) {
    final Map<String, double> sum = <String, double>{};
    void add(String k, double v) => sum[k] = (sum[k] ?? 0) + v;

    final List<String> counted = <String>[];
    final List<String> skipped = <String>[];

    for (final DraftIngredient i in items) {
      final Food? f = match(i.name);
      final double? g =
          f == null || i.quantity <= 0 ? null : grams(f, i.quantity, i.unit);
      if (f == null || g == null) {
        if (i.unit != MeasureUnit.toTaste) skipped.add(i.name);
        continue;
      }
      counted.add(i.name);
      final double s = g / 100;
      add('calories', f.kcal * s);
      add('protein_g', f.protein * s);
      add('carbs_g', f.carbs * s);
      add('fat_g', f.fat * s);
      add('fiber_g', f.fiber * s);
      add('sugar_g', f.sugar * s);
      if (f.addedSugar) add('added_sugar_g', f.sugar * s);
      add('sat_fat_g', f.satFat * s);
      add('sodium_mg', f.sodium * s);
      add('cholesterol_mg', f.cholesterol * s);
      add('potassium_mg', f.potassium * s);
      add('calcium_mg', f.calcium * s);
      add('iron_mg', f.iron * s);
      add('vitamin_c_mg', f.vitC * s);
      final List<double>? micro = kFoodMicros[f.names.split('|').first];
      if (micro != null) {
        for (int k = 0; k < kMicroOrder.length; k++) {
          add(kMicroOrder[k], micro[k] * s);
        }
      }
    }

    final int n = servings < 1 ? 1 : servings;
    final Map<String, double> perServing = <String, double>{
      for (final MapEntry<String, double> e in sum.entries)
        e.key: (e.value / n * 100).round() / 100,
    };
    return NutritionEstimate(
      nutrition: Nutrition(values: perServing),
      counted: counted,
      skipped: skipped,
    );
  }
}
