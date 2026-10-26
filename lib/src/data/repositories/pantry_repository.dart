import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../models/enums.dart';
import '../models/models.dart';

class PantryRepository {
  PantryRepository(this._client);

  final SupabaseClient _client;

  Future<List<PantryItem>> list(String libraryId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('pantry_items')
          .select('id, ingredient_id, quantity, unit, '
              'ingredients(name, grocery_category)')
          .eq('library_id', libraryId)
          .order('updated_at', ascending: false);
      return rows.map(PantryItem.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> upsert({
    required String libraryId,
    required String ingredientId,
    required double quantity,
    required MeasureUnit unit,
  }) async {
    try {
      await _client.from('pantry_items').upsert(
        <String, dynamic>{
          'library_id': libraryId,
          'ingredient_id': ingredientId,
          'quantity': quantity,
          'unit': unit.wire,
        },
        onConflict: 'library_id,ingredient_id',
      );
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> remove(String pantryItemId) async {
    try {
      await _client.from('pantry_items').delete().eq('id', pantryItemId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// The matcher. All of the work happens in Postgres: sending every
  /// recipe's ingredient list to the device to intersect it there would
  /// mean shipping the whole recipe box on every pantry change.
  Future<List<PantryMatch>> match({
    required String libraryId,
    int minimumPercent = 0,
    MealType? mealType,
    Season? season,
    int limit = 50,
  }) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'pantry_match',
        params: <String, dynamic>{
          'p_library_id': libraryId,
          'p_min_pct': minimumPercent,
          'p_meal_type': mealType?.wire,
          'p_season': season?.wire,
          'p_limit': limit,
        },
      );
      if (result is! List) return const <PantryMatch>[];
      return result
          .whereType<Map<String, dynamic>>()
          .map(PantryMatch.fromJson)
          .toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
