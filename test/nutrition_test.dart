import 'package:flutter_test/flutter_test.dart';
import 'package:cookistrybook/src/data/models/models.dart';

void main() {
  test('Nutrition decodes, scales percent DV and macro split', () {
    final Nutrition n = Nutrition.fromJson(<String, dynamic>{
      'calories': 400,
      'fat_g': '39.0',
      'sodium_mg': 1150,
      'protein_g': 25,
      'carbs_g': 50,
      'serving_size': '1 bowl',
    });
    expect(n.calories, 400);
    expect(n.servingSize, '1 bowl');
    final NutrientDef fat =
        kLabelNutrients.firstWhere((NutrientDef d) => d.key == 'fat_g');
    final NutrientDef sodium =
        kLabelNutrients.firstWhere((NutrientDef d) => d.key == 'sodium_mg');
    expect(n.percentDv(fat), 50);
    expect(n.percentDv(sodium), 50);
    final split = n.macroSplit!;
    expect(split.carbs + split.fat + split.protein, closeTo(1, 1e-9));
  });

  test('Nutrition toJson clamps and clears unset values', () {
    final Nutrition n = const Nutrition()
        .withValue('calories', 99999)
        .withValue('iron_mg', 2.5)
        .withServingSize('  ');
    final Map<String, Object?> j = n.toJson();
    expect(j['calories'], 5000);
    expect(j['iron_mg'], 2.5);
    expect(j['sodium_mg'], isNull);
    expect(j['serving_size'], isNull);
    expect(const Nutrition().isEmpty, isTrue);
  });
}
