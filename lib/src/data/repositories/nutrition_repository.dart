import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../models/models.dart';

/// Personal daily targets. Protein, carbs and fat are stored in grams;
/// the UI edits them as a percentage split of the calorie goal.
class NutritionGoals {
  const NutritionGoals({
    this.calories = 2000,
    this.proteinG = 100,
    this.carbsG = 250,
    this.fatG = 67,
    this.fiberG = 28,
    this.sugarG = 50,
    this.sodiumMg = 2300,
  });

  final int calories;
  final double proteinG, carbsG, fatG, fiberG, sugarG;
  final int sodiumMg;

  /// Builds gram targets from a calorie goal and a % split (4/4/9 kcal/g).
  factory NutritionGoals.fromSplit({
    required int calories,
    required int carbsPct,
    required int proteinPct,
    required int fatPct,
    double fiberG = 28,
    double sugarG = 50,
    int sodiumMg = 2300,
  }) {
    double g(int pct, double kcalPerGram) =>
        ((calories * pct / 100) / kcalPerGram * 10).round() / 10;
    return NutritionGoals(
      calories: calories,
      carbsG: g(carbsPct, 4),
      proteinG: g(proteinPct, 4),
      fatG: g(fatPct, 9),
      fiberG: fiberG,
      sugarG: sugarG,
      sodiumMg: sodiumMg,
    );
  }

  int get carbsPct => _pct(carbsG * 4);
  int get proteinPct => _pct(proteinG * 4);
  int get fatPct => _pct(fatG * 9);

  int _pct(double kcal) => calories <= 0 ? 0 : (kcal / calories * 100).round();

  /// Daily target for a nutrient key, falling back to the FDA Daily Value.
  double? targetFor(NutrientDef d) {
    switch (d.key) {
      case 'calories':
        return calories.toDouble();
      case 'protein_g':
        return proteinG;
      case 'carbs_g':
        return carbsG;
      case 'fat_g':
        return fatG;
      case 'fiber_g':
        return fiberG;
      case 'sugar_g':
        return sugarG;
      case 'sodium_mg':
        return sodiumMg.toDouble();
      default:
        return d.dailyValue;
    }
  }

  factory NutritionGoals.fromJson(Map<String, dynamic> j) {
    double d(Object? v, double f) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? f;
    return NutritionGoals(
      calories: d(j['calories'], 2000).round(),
      proteinG: d(j['protein_g'], 100),
      carbsG: d(j['carbs_g'], 250),
      fatG: d(j['fat_g'], 67),
      fiberG: d(j['fiber_g'], 28),
      sugarG: d(j['sugar_g'], 50),
      sodiumMg: d(j['sodium_mg'], 2300).round(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'calories': calories.clamp(500, 10000),
        'protein_g': proteinG.clamp(0, 1000),
        'carbs_g': carbsG.clamp(0, 1500),
        'fat_g': fatG.clamp(0, 600),
        'fiber_g': fiberG.clamp(0, 300),
        'sugar_g': sugarG.clamp(0, 1000),
        'sodium_mg': sodiumMg.clamp(0, 20000),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

const List<String> kMeals = <String>['breakfast', 'lunch', 'dinner', 'snack'];

String mealLabel(String m) =>
    m.isEmpty ? m : m[0].toUpperCase() + m.substring(1);

class FoodLogEntry {
  const FoodLogEntry({
    required this.id,
    required this.day,
    required this.meal,
    required this.title,
    required this.servings,
    required this.nutrition,
    this.recipeId,
  });

  final String id;
  final DateTime day;
  final String meal;
  final String title;
  final double servings;
  final String? recipeId;

  /// Totals for this entry (already multiplied by servings).
  final Nutrition nutrition;

  factory FoodLogEntry.fromJson(Map<String, dynamic> j) {
    final Object? n = j['nutrition'];
    return FoodLogEntry(
      id: '${j['id']}',
      day: DateTime.parse('${j['logged_on']}'),
      meal: '${j['meal']}',
      title: '${j['title']}',
      servings: (j['servings'] as num?)?.toDouble() ?? 1,
      recipeId: j['recipe_id'] as String?,
      nutrition: Nutrition(values: <String, double>{
        if (n is Map)
          for (final MapEntry<dynamic, dynamic> e in n.entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      }),
    );
  }
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class NutritionRepository {
  NutritionRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const Failure('Sign in to track nutrition.');
    return id;
  }

  Future<NutritionGoals> goals() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('nutrition_goals')
          .select()
          .eq('user_id', _uid)
          .maybeSingle();
      return row == null
          ? const NutritionGoals()
          : NutritionGoals.fromJson(row);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> saveGoals(NutritionGoals g) async {
    try {
      await _client
          .from('nutrition_goals')
          .upsert(<String, dynamic>{'user_id': _uid, ...g.toJson()});
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<List<FoodLogEntry>> entries(DateTime from, DateTime to) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('food_log')
          .select('id, logged_on, meal, title, servings, recipe_id, nutrition')
          .eq('user_id', _uid)
          .gte('logged_on', dayKey(from))
          .lte('logged_on', dayKey(to))
          .order('created_at');
      return rows.map(FoodLogEntry.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// [perServing] is multiplied by [servings] before it is stored, so a
  /// later edit of the recipe never rewrites past diary days.
  Future<void> add({
    required DateTime day,
    required String meal,
    required String title,
    required double servings,
    required Nutrition perServing,
    String? recipeId,
  }) async {
    final String clean = InputSanitizer.singleLine(title, maxLength: 160);
    if (clean.isEmpty) throw const Failure('Give the entry a name.');
    if (!kMeals.contains(meal)) throw const Failure('Pick a meal.');
    final double s = servings.clamp(0.1, 100).toDouble();
    final Nutrition total = perServing.scaled(s);
    try {
      await _client.from('food_log').insert(<String, dynamic>{
        'user_id': _uid,
        'logged_on': dayKey(day),
        'meal': meal,
        'title': clean,
        'recipe_id': recipeId,
        'servings': s,
        'nutrition': <String, double>{
          for (final MapEntry<String, double> e in total.values.entries)
            e.key: (e.value * 100).round() / 100,
        },
      });
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('food_log').delete().eq('id', id).eq('user_id', _uid);
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
