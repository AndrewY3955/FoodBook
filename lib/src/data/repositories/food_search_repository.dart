import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../models/food_item.dart';

/// Live food and restaurant lookup through the food-search Edge Function
/// (USDA FoodData Central + Open Food Facts). The API key stays on the
/// server; the device only ever sends the search text.
class FoodSearchRepository {
  FoodSearchRepository(this._client);

  final SupabaseClient _client;

  final Map<String, List<FoodItem>> _cache = <String, List<FoodItem>>{};

  Future<List<FoodItem>> search(String rawQuery, {int page = 1}) async {
    final String query = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 2) return const <FoodItem>[];
    final String key = '$page|${query.toLowerCase()}';
    final List<FoodItem>? hit = _cache[key];
    if (hit != null) return hit;

    try {
      final FunctionResponse response = await _client.functions.invoke(
        'food-search',
        body: <String, dynamic>{'query': query, 'page': page},
      );
      if (response.status == 429) {
        throw const Failure('Too many searches just now. Try again shortly.');
      }
      final Object? data = response.data;
      if (response.status != 200 || data is! Map<String, dynamic>) {
        throw const Failure('Food search is unavailable right now.');
      }
      final Object? foods = data['foods'];
      final List<FoodItem> items = <FoodItem>[
        if (foods is List)
          for (final Object? f in foods)
            if (f is Map<String, dynamic>) FoodItem.fromJson(f),
      ];
      if (_cache.length >= 100) _cache.clear();
      _cache[key] = items;
      return items;
    } on FunctionException catch (_) {
      throw const Failure('Food search is unavailable right now.');
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
