import 'models/enums.dart';
import 'models/food_item.dart';
import 'models/nutrition.dart';
import 'nutrition_db.dart';
import 'nutrition_micros.dart';
import 'repositories/recipe_repository.dart';

class NutritionEstimate {
  const NutritionEstimate({
    required this.nutrition,
    required this.counted,
    required this.skipped,
    required this.skippedReasons,
    required this.incompleteNutrients,
  });

  /// Per serving.
  final Nutrition nutrition;
  final List<String> counted;

  /// Ingredients that could not be matched or converted to a weight.
  final List<String> skipped;

  /// Human-readable explanation for each skipped ingredient name.
  final Map<String, String> skippedReasons;

  /// Nutrients omitted because at least one counted ingredient lacks data.
  final List<String> incompleteNutrients;
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
  /// Explicit preparation states must agree with the stored food variant.
  static Food? match(String name) {
    final String n = name.toLowerCase().replaceAll(RegExp(r'[^a-z\- ]'), ' ');
    final String? requestedPreparation = _preparation(n);
    final bool needsPreparation = RegExp(
      r'\b(rice|pasta|noodles|quinoa|oats|beans?|chickpeas?|garbanzo|lentils?)\b',
    ).hasMatch(n);
    if (needsPreparation && requestedPreparation == null) return null;
    Food? best;
    int bestLen = 0;
    for (final MapEntry<Food, List<RegExp>> e in _patterns.entries) {
      final List<String> phrases = e.key.names.split('|');
      for (int i = 0; i < phrases.length; i++) {
        final String phrase = phrases[i];
        if (phrase.length <= bestLen || !e.value[i].hasMatch(n)) continue;
        final String? storedPreparation = _preparation(phrase);
        final bool preparationMatches = requestedPreparation == 'raw/dry'
            ? storedPreparation == null || storedPreparation == 'raw/dry'
            : storedPreparation == requestedPreparation;
        if (!preparationMatches) continue;
        best = e.key;
        bestLen = phrase.length;
      }
    }
    return best;
  }

  /// Normalize only explicit preparation words. Boiled and steamed foods
  /// are grouped with cooked foods; other methods remain distinct.
  static String? _preparation(String value) {
    final String normalized = value.toLowerCase();
    if (RegExp(r'\b(raw|dry)\b').hasMatch(normalized)) return 'raw/dry';
    if (RegExp(r'\b(cooked|boiled|steamed)\b').hasMatch(normalized)) {
      return 'cooked';
    }
    final RegExp other = RegExp(
      r'\b(grilled|roasted|fried|baked|smoked|dried|dehydrated|canned|drained)\b',
    );
    return other.firstMatch(normalized)?.group(0);
  }

  /// Grams for [qty] of [unit] of [food], or null when it cannot be known.
  static double? grams(Food food, double qty, MeasureUnit unit) =>
      _grams(food.gramsPerCup, food.gramsEach, qty, unit);

  /// Same for an online food. Only mass units are universally convertible
  /// without food-specific density data. A labelled serving weight does not
  /// establish the weight of an individual piece, clove, or slice.
  static double? gramsOnline(FoodItem food, double qty, MeasureUnit unit) =>
      _grams(null, null, qty, unit);

  static double? _grams(
      double? cup, double? each, double qty, MeasureUnit unit) {
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
        return each == null ? null : qty * each;
      case MeasureUnit.bunch:
      case MeasureUnit.can:
      case MeasureUnit.package:
      case MeasureUnit.toTaste:
        return null;
    }
  }

  /// Per-serving estimate. [online] maps an ingredient name to a food
  /// found by live search; it is used only when the built-in table has
  /// no match for that ingredient.
  static NutritionEstimate estimate(
    List<DraftIngredient> items,
    int servings, {
    Map<String, FoodItem> online = const <String, FoodItem>{},
  }) {
    final Map<String, double> sum = <String, double>{};
    final Set<String> incompleteNutrients = <String>{};
    void add(String k, double v) => sum[k] = (sum[k] ?? 0) + v;

    final List<String> counted = <String>[];
    final List<String> skipped = <String>[];
    final Map<String, String> skippedReasons = <String, String>{};

    for (final DraftIngredient i in items) {
      if (i.unit == MeasureUnit.toTaste) continue;
      if (i.quantity <= 0) {
        skipped.add(i.name);
        skippedReasons[i.name] = 'Enter an amount greater than zero.';
        continue;
      }

      final Food? f = match(i.name);
      final FoodItem? o = f == null ? online[i.name] : null;
      if (o != null) {
        final double? onlineGrams = gramsOnline(o, i.quantity, i.unit);
        if (onlineGrams == null) {
          final String unit =
              i.unit.label.isEmpty ? i.unit.wire : i.unit.label;
          skipped.add(i.name);
          skippedReasons[i.name] =
              'No reliable conversion from $unit to grams is available '
              'for this food. Enter its weight in grams or use a supported '
              'mass unit.';
          continue;
        }
        counted.add(i.name);
        for (final NutrientDef nutrient in kAllNutrients) {
          final double? value = o.per100g[nutrient.key];
          if (value == null) {
            incompleteNutrients.add(nutrient.key);
          } else {
            add(nutrient.key, value * onlineGrams / 100);
          }
        }
        continue;
      }

      final double? g = f == null ? null : grams(f, i.quantity, i.unit);
      if (f == null || g == null) {
        skipped.add(i.name);
        skippedReasons[i.name] = f == null
            ? 'No matching food data was found.'
            : 'The selected amount cannot be converted to weight using '
                'the available food data.';
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
      add('added_sugar_g', (f.addedSugar ? f.sugar : 0) * s);
      add('sat_fat_g', f.satFat * s);
      add('sodium_mg', f.sodium * s);
      add('cholesterol_mg', f.cholesterol * s);
      add('potassium_mg', f.potassium * s);
      add('calcium_mg', f.calcium * s);
      add('iron_mg', f.iron * s);
      add('vitamin_c_mg', f.vitC * s);
      final List<double>? micro = kFoodMicros[f.names.split('|').first];
      if (micro == null) {
        // An absent database row means "not reported", not zero.
        incompleteNutrients.addAll(kMicroOrder);
      } else {
        for (int k = 0; k < kMicroOrder.length; k++) {
          add(kMicroOrder[k], micro[k] * s);
        }
      }
    }

    // Never publish a partial sum as if every ingredient had known data.
    for (final String key in incompleteNutrients) {
      sum.remove(key);
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
      skippedReasons: skippedReasons,
      incompleteNutrients: incompleteNutrients.toList(growable: false),
    );
  }
}
