import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../../core/security/postgrest_safe.dart';
import '../models/enums.dart';
import '../models/models.dart';

class IngredientRepository {
  IngredientRepository(this._client);

  final SupabaseClient _client;

  /// Autocomplete over the shared catalog plus this library's own
  /// additions. The trigram index on ingredients.name is what keeps the
  /// ilike from degrading into a sequential scan.
  Future<List<Ingredient>> search({
    required String libraryId,
    required String query,
    int limit = 20,
  }) async {
    // Validated before it can reach a filter expression, not merely
    // trusted because of where it came from.
    final String library =
        PostgrestSafe.requireUuid(libraryId, 'libraryId');
    final String? pattern = PostgrestSafe.likePattern(
        InputSanitizer.singleLine(query, maxLength: 60));

    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> builder = _client
          .from('ingredients')
          .select(
              'id, name, grocery_category, default_unit, library_id')
          .or('library_id.is.null,library_id.eq.$library');

      if (pattern != null) builder = builder.ilike('name', pattern);

      final List<Map<String, dynamic>> rows =
          await builder.order('name').limit(limit);
      return rows.map(Ingredient.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<List<Ingredient>> all(String libraryId) =>
      search(libraryId: libraryId, query: '', limit: 500);

  /// Finds a catalog entry by exact name, or creates a library-private
  /// one. Used by the import parser, where the incoming text is
  /// whatever a stranger typed into a caption.
  Future<Ingredient> findOrCreate({
    required String libraryId,
    required String name,
    GroceryCategory category = GroceryCategory.other,
    MeasureUnit defaultUnit = MeasureUnit.unit,
  }) async {
    final String clean = InputSanitizer.singleLine(name, maxLength: 80);
    if (clean.isEmpty) throw const Failure('That ingredient has no name.');

    final String library =
        PostgrestSafe.requireUuid(libraryId, 'libraryId');
    // Exact-match lookup: the term is stripped of wildcard characters so
    // a name containing '%' cannot broaden the match.
    final String exact = PostgrestSafe.likeExact(clean);

    try {
      final List<Map<String, dynamic>> existing = await _client
          .from('ingredients')
          .select(
              'id, name, grocery_category, default_unit, library_id')
          .or('library_id.is.null,library_id.eq.$library')
          .ilike('name', exact)
          .limit(1);

      if (existing.isNotEmpty) return Ingredient.fromJson(existing.first);

      final Map<String, dynamic> created = await _client
          .from('ingredients')
          .insert(<String, dynamic>{
            'library_id': libraryId,
            'name': clean,
            'grocery_category': category.wire,
            'default_unit': defaultUnit.wire,
          })
          .select(
              'id, name, grocery_category, default_unit, library_id')
          .single();

      return Ingredient.fromJson(created);
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
