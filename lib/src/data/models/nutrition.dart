/// One nutrient on the label: its database column, display name, unit,
/// FDA Daily Value (for the %DV column) and how it is laid out.
class NutrientDef {
  const NutrientDef(
    this.key,
    this.label,
    this.unit, {
    this.dailyValue,
    this.indent = 0,
    this.bold = false,
    this.max = 500,
    this.whole = false,
    this.extra = false,
  });

  final String key;
  final String label;
  final String unit;
  final double? dailyValue;
  final int indent;
  final bool bold;
  final double max;

  /// Stored as an integer column (no decimals).
  final bool whole;

  /// Stored inside the recipes.micros jsonb column rather than its own column.
  final bool extra;
}

const NutrientDef kCalories =
    NutrientDef('calories', 'Calories', '', max: 5000, whole: true);

/// Label order follows the US Nutrition Facts panel. Daily Values are the
/// current FDA reference amounts for adults (2,000 kcal diet).
const List<NutrientDef> kLabelNutrients = <NutrientDef>[
  NutrientDef('fat_g', 'Total Fat', 'g', dailyValue: 78, bold: true),
  NutrientDef('sat_fat_g', 'Saturated Fat', 'g', dailyValue: 20, indent: 1),
  NutrientDef('trans_fat_g', 'Trans Fat', 'g', indent: 1),
  NutrientDef('poly_fat_g', 'Polyunsaturated Fat', 'g', indent: 1),
  NutrientDef('mono_fat_g', 'Monounsaturated Fat', 'g', indent: 1),
  NutrientDef('cholesterol_mg', 'Cholesterol', 'mg',
      dailyValue: 300, bold: true, max: 20000, whole: true),
  NutrientDef('sodium_mg', 'Sodium', 'mg',
      dailyValue: 2300, bold: true, max: 20000, whole: true),
  NutrientDef('carbs_g', 'Total Carbohydrate', 'g',
      dailyValue: 275, bold: true),
  NutrientDef('fiber_g', 'Dietary Fiber', 'g', dailyValue: 28, indent: 1),
  NutrientDef('sugar_g', 'Total Sugars', 'g', indent: 1),
  NutrientDef('added_sugar_g', 'Added Sugars', 'g', dailyValue: 50, indent: 2),
  NutrientDef('protein_g', 'Protein', 'g', dailyValue: 50, bold: true),
  NutrientDef('vitamin_d_mcg', 'Vitamin D', 'mcg', dailyValue: 20, max: 5000),
  NutrientDef('calcium_mg', 'Calcium', 'mg',
      dailyValue: 1300, max: 20000, whole: true),
  NutrientDef('iron_mg', 'Iron', 'mg', dailyValue: 18),
  NutrientDef('potassium_mg', 'Potassium', 'mg',
      dailyValue: 4700, max: 20000, whole: true),
  NutrientDef('vitamin_a_mcg', 'Vitamin A', 'mcg',
      dailyValue: 900, max: 50000, whole: true),
  NutrientDef('vitamin_c_mg', 'Vitamin C', 'mg', dailyValue: 90, max: 5000),
];

/// More vitamins and minerals, kept in the micros jsonb column. Daily
/// Values are the FDA adult reference amounts.
const List<NutrientDef> kMicroExtras = <NutrientDef>[
  NutrientDef('vitamin_e_mg', 'Vitamin E', 'mg', dailyValue: 15, extra: true),
  NutrientDef('vitamin_k_mcg', 'Vitamin K', 'mcg',
      dailyValue: 120, extra: true, max: 5000),
  NutrientDef('thiamin_mg', 'Thiamin (B1)', 'mg', dailyValue: 1.2, extra: true),
  NutrientDef('riboflavin_mg', 'Riboflavin (B2)', 'mg',
      dailyValue: 1.3, extra: true),
  NutrientDef('niacin_mg', 'Niacin (B3)', 'mg', dailyValue: 16, extra: true),
  NutrientDef('vitamin_b6_mg', 'Vitamin B6', 'mg',
      dailyValue: 1.7, extra: true),
  NutrientDef('folate_mcg', 'Folate', 'mcg',
      dailyValue: 400, extra: true, max: 5000),
  NutrientDef('vitamin_b12_mcg', 'Vitamin B12', 'mcg',
      dailyValue: 2.4, extra: true),
  NutrientDef('magnesium_mg', 'Magnesium', 'mg',
      dailyValue: 420, extra: true, max: 5000),
  NutrientDef('phosphorus_mg', 'Phosphorus', 'mg',
      dailyValue: 1250, extra: true, max: 10000),
  NutrientDef('zinc_mg', 'Zinc', 'mg', dailyValue: 11, extra: true),
  NutrientDef('selenium_mcg', 'Selenium', 'mcg',
      dailyValue: 55, extra: true, max: 2000),
];

/// Vitamins and minerals shown as "% of daily value" bars.
final List<NutrientDef> kVitaminMineralDefs = <NutrientDef>[
  ...kLabelNutrients.skipWhile((NutrientDef d) => d.key != 'vitamin_d_mcg'),
  ...kMicroExtras,
];

const List<String> kVitaminKeys = <String>[
  'vitamin_a_mcg',
  'vitamin_c_mg',
  'vitamin_d_mcg',
  'vitamin_e_mg',
  'vitamin_k_mcg',
  'thiamin_mg',
  'riboflavin_mg',
  'niacin_mg',
  'vitamin_b6_mg',
  'folate_mcg',
  'vitamin_b12_mcg',
];

final List<NutrientDef> kAllNutrients = <NutrientDef>[
  kCalories,
  ...kLabelNutrients,
  ...kMicroExtras,
];

/// Every real column read from the recipes table for nutrition.
final String kNutritionColumns = 'serving_size, micros, '
    '${kAllNutrients.where((NutrientDef d) => !d.extra).map((NutrientDef d) => d.key).join(', ')}';

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Nutrition facts per serving. Every value is optional; most people only
/// know a few. Values are keyed by [NutrientDef.key].
class Nutrition {
  const Nutrition({
    this.values = const <String, double>{},
    this.servingSize,
  });

  static const Nutrition empty = Nutrition();

  final Map<String, double> values;

  /// Free text such as "1 cup (240 g)".
  final String? servingSize;

  double? operator [](String key) => values[key];

  int? get calories => values['calories']?.round();
  double? get proteinG => values['protein_g'];
  double? get carbsG => values['carbs_g'];
  double? get fatG => values['fat_g'];

  bool get isEmpty =>
      values.isEmpty && (servingSize == null || servingSize!.isEmpty);

  /// Sets or clears (null) one nutrient.
  Nutrition withValue(String key, double? v) {
    final Map<String, double> next = Map<String, double>.of(values);
    if (v == null) {
      next.remove(key);
    } else {
      next[key] = v;
    }
    return Nutrition(values: next, servingSize: servingSize);
  }

  /// Every value multiplied by [factor] (servings eaten).
  Nutrition scaled(double factor) => Nutrition(
        values: <String, double>{
          for (final MapEntry<String, double> e in values.entries)
            e.key: e.value * factor,
        },
        servingSize: servingSize,
      );

  /// Sum of several nutrition totals.
  static Map<String, double> sum(Iterable<Nutrition> items) {
    final Map<String, double> out = <String, double>{};
    for (final Nutrition n in items) {
      n.values.forEach((String k, double v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  Nutrition withServingSize(String? s) => Nutrition(
        values: values,
        servingSize: (s == null || s.trim().isEmpty) ? null : s,
      );

  factory Nutrition.fromJson(Map<String, dynamic> json) {
    final Map<String, double> out = <String, double>{};
    final Object? micros = json['micros'];
    for (final NutrientDef d in kAllNutrients) {
      final Object? raw =
          d.extra ? (micros is Map ? micros[d.key] : null) : json[d.key];
      final double? v = _num(raw);
      if (v != null) out[d.key] = v;
    }
    final Object? s = json['serving_size'];
    return Nutrition(
      values: out,
      servingSize: s is String && s.isNotEmpty ? s : null,
    );
  }

  /// Column map for saving, clamped to the database CHECK ranges.
  Map<String, Object?> toJson() {
    final String s = (servingSize ?? '').trim();
    final Map<String, Object?> out = <String, Object?>{
      'serving_size':
          s.isEmpty ? null : (s.length > 80 ? s.substring(0, 80) : s),
    };
    final Map<String, double> micros = <String, double>{};
    for (final NutrientDef d in kAllNutrients) {
      final double? v = values[d.key];
      if (d.extra) {
        if (v != null) micros[d.key] = v.clamp(0, d.max).toDouble();
        continue;
      }
      if (v == null) {
        out[d.key] = null;
      } else {
        final double c = v.clamp(0, d.max).toDouble();
        out[d.key] = d.whole ? c.round() : c;
      }
    }
    out['micros'] = micros;
    return out;
  }

  /// Calories from macros (4/9/4 rule), used for the macro split.
  double get _macroKcal =>
      (proteinG ?? 0) * 4 + (carbsG ?? 0) * 4 + (fatG ?? 0) * 9;

  /// Share of calories from carbs, fat, protein (0..1 each), or null when
  /// no macros are known.
  ({double carbs, double fat, double protein})? get macroSplit {
    final double total = _macroKcal;
    if (total <= 0) return null;
    return (
      carbs: (carbsG ?? 0) * 4 / total,
      fat: (fatG ?? 0) * 9 / total,
      protein: (proteinG ?? 0) * 4 / total,
    );
  }

  /// Percent of the Daily Value for [d], or null when unknown.
  int? percentDv(NutrientDef d) {
    final double? v = values[d.key];
    final double? dv = d.dailyValue;
    if (v == null || dv == null) return null;
    return (v / dv * 100).round();
  }
}
