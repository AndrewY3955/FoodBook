import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../models/enums.dart';
import '../models/models.dart';

class MealPlanRepository {
  MealPlanRepository(this._client);

  final SupabaseClient _client;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<List<MealPlanEntry>> range({
    required String libraryId,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('meal_plan_entries')
          .select('id, recipe_id, plan_date, meal_type, servings_override, '
              'note, recipes(title, cover_image_path)')
          .eq('library_id', libraryId)
          .gte('plan_date', _dateOnly(from))
          .lte('plan_date', _dateOnly(to))
          .order('plan_date');
      return rows.map(MealPlanEntry.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> add({
    required String libraryId,
    required String recipeId,
    required DateTime date,
    required MealType mealType,
    int? servingsOverride,
    String? note,
  }) async {
    try {
      await _client.from('meal_plan_entries').insert(<String, dynamic>{
        'library_id': libraryId,
        'recipe_id': recipeId,
        'plan_date': _dateOnly(date),
        'meal_type': mealType.wire,
        'servings_override': servingsOverride,
        'note': note == null
            ? null
            : InputSanitizer.singleLine(note, maxLength: 280),
        'created_by': _client.auth.currentUser?.id,
      });
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> move({
    required String entryId,
    required DateTime date,
    required MealType mealType,
  }) async {
    try {
      await _client.from('meal_plan_entries').update(<String, dynamic>{
        'plan_date': _dateOnly(date),
        'meal_type': mealType.wire,
      }).eq('id', entryId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> remove(String entryId) async {
    try {
      await _client.from('meal_plan_entries').delete().eq('id', entryId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Everything planned in the window, pushed to the shopping list in
  /// one pass. Sequential rather than parallel: the aggregation function
  /// merges into existing rows, and concurrent merges on the same
  /// ingredient would race under last-write-wins.
  Future<int> addRangeToShoppingList({
    required String libraryId,
    required DateTime from,
    required DateTime to,
  }) async {
    final List<MealPlanEntry> entries =
        await range(libraryId: libraryId, from: from, to: to);

    int touched = 0;
    for (final MealPlanEntry entry in entries) {
      try {
        final dynamic result = await _client.rpc<dynamic>(
          'add_recipe_to_shopping_list',
          params: <String, dynamic>{
            'p_recipe_id': entry.recipeId,
            'p_library_id': libraryId,
            'p_servings': entry.servingsOverride,
            'p_skip_pantry': true,
          },
        );
        touched += result is int ? result : 0;
      } catch (error) {
        throw Failure.from(error);
      }
    }
    return touched;
  }
}
