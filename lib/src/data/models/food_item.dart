import 'nutrition.dart';

/// One result from the live food search (USDA FoodData Central or Open
/// Food Facts). Values are per 100 g; [nutritionFor] scales them.
class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    required this.per100g,
    this.brand,
    this.category,
    this.source = '',
    this.dataType = '',
    this.servingGrams,
    this.servingLabel,
  });

  final String id;
  final String name;
  final String? brand;
  final String? category;

  /// 'usda' or 'off'.
  final String source;
  final String dataType;
  final Nutrition per100g;

  /// Grams in one labelled serving, when the source reports it.
  final double? servingGrams;
  final String? servingLabel;

  bool get isBranded => brand != null && brand!.isNotEmpty;

  String get sourceLabel => source == 'off' ? 'Open Food Facts' : 'USDA';

  String get displayName => isBranded ? '$name ($brand)' : name;

  /// Nutrition for [grams] of this food.
  Nutrition nutritionFor(double grams) => per100g.scaled(grams / 100);

  factory FoodItem.fromJson(Map<String, dynamic> j) {
    final Object? raw = j['per100g'];
    final Map<String, double> values = <String, double>{
      if (raw is Map)
        for (final MapEntry<dynamic, dynamic> e in raw.entries)
          if (e.value is num) '${e.key}': (e.value as num).toDouble(),
    };
    final double? grams = (j['servingGrams'] as num?)?.toDouble();
    return FoodItem(
      id: '${j['id']}',
      name: '${j['name']}',
      brand: j['brand'] as String?,
      category: j['category'] as String?,
      source: '${j['source'] ?? ''}',
      dataType: '${j['dataType'] ?? ''}',
      per100g: Nutrition(values: values),
      servingGrams: grams != null && grams > 0 ? grams : null,
      servingLabel: j['servingLabel'] as String?,
    );
  }
}
