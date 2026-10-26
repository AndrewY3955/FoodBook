import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../models/enums.dart';
import '../models/models.dart';

class ShoppingRepository {
  ShoppingRepository(this._client);

  final SupabaseClient _client;

  Future<List<ShoppingItem>> list(String libraryId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('shopping_list_items')
          .select('id, ingredient_id, custom_name, grocery_category, '
              'quantity, unit, is_checked, created_at, ingredients(name)')
          .eq('library_id', libraryId)
          .order('created_at');
      return rows.map(ShoppingItem.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Groups into the fixed category order defined by the enum. Empty
  /// categories are dropped so the list does not become a wall of
  /// headings with nothing under them.
  static Map<GroceryCategory, List<ShoppingItem>> group(
    List<ShoppingItem> items,
  ) {
    final Map<GroceryCategory, List<ShoppingItem>> grouped =
        <GroceryCategory, List<ShoppingItem>>{};
    for (final GroceryCategory category in GroceryCategory.values) {
      final List<ShoppingItem> inCategory = items
          .where((ShoppingItem i) => i.category == category)
          .toList(growable: false);
      if (inCategory.isNotEmpty) {
        // Unchecked first, then alphabetical: ticking something off
        // moves it down rather than making it vanish.
        final List<ShoppingItem> sorted = List<ShoppingItem>.of(inCategory)
          ..sort((ShoppingItem a, ShoppingItem b) {
            if (a.isChecked != b.isChecked) return a.isChecked ? 1 : -1;
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          });
        grouped[category] = sorted;
      }
    }
    return grouped;
  }

  Future<void> addCustom({
    required String libraryId,
    required String label,
    required GroceryCategory category,
    double quantity = 1,
    MeasureUnit unit = MeasureUnit.unit,
  }) async {
    final String clean = InputSanitizer.singleLine(label, maxLength: 80);
    if (clean.isEmpty) throw const Failure('Type something to add.');
    try {
      await _client.from('shopping_list_items').insert(<String, dynamic>{
        'library_id': libraryId,
        'custom_name': clean,
        'grocery_category': category.wire,
        'quantity': quantity,
        'unit': unit.wire,
        'added_by': _client.auth.currentUser?.id,
      });
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> setChecked(String itemId, bool isChecked) async {
    try {
      await _client
          .from('shopping_list_items')
          .update(<String, dynamic>{'is_checked': isChecked}).eq('id', itemId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> setQuantity(String itemId, double quantity) async {
    if (quantity <= 0) return remove(itemId);
    try {
      await _client
          .from('shopping_list_items')
          .update(<String, dynamic>{'quantity': quantity}).eq('id', itemId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> remove(String itemId) async {
    try {
      await _client.from('shopping_list_items').delete().eq('id', itemId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> clearChecked(String libraryId) async {
    try {
      await _client
          .from('shopping_list_items')
          .delete()
          .eq('library_id', libraryId)
          .eq('is_checked', true);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Server-side aggregation: scales to the requested servings, skips
  /// what the pantry already holds, and merges into existing rows
  /// instead of duplicating them. Returns the number of rows touched.
  Future<int> addRecipe({
    required String recipeId,
    required String libraryId,
    int? servings,
    bool skipPantry = true,
  }) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'add_recipe_to_shopping_list',
        params: <String, dynamic>{
          'p_recipe_id': recipeId,
          'p_library_id': libraryId,
          'p_servings': servings,
          'p_skip_pantry': skipPantry,
        },
      );
      return result is int ? result : 0;
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
