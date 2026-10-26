import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../../core/security/postgrest_safe.dart';
import '../models/enums.dart';
import '../models/models.dart';

/// Draft types used when creating or editing. They exist so the form
/// controller can hold half-finished input without pretending it is a
/// valid Recipe.
class DraftIngredient {
  DraftIngredient({
    required this.ingredientId,
    required this.name,
    this.quantity = 1,
    this.unit = MeasureUnit.unit,
    this.note,
    this.isOptional = false,
  });

  final String ingredientId;
  final String name;
  double quantity;
  MeasureUnit unit;
  String? note;
  bool isOptional;
}

class DraftStep {
  DraftStep({required this.instruction, this.timerSeconds});

  String instruction;
  int? timerSeconds;
}

class RecipeDraft {
  RecipeDraft({
    this.id,
    this.title = '',
    this.description = '',
    this.mealType = MealType.dinner,
    this.season = Season.allYear,
    this.baseServings = 4,
    this.prepMinutes,
    this.cookMinutes,
    this.externalVideoUrl,
    this.sourceUrl,
    this.isPublic = false,
    this.importSource = ImportSource.manual,
    this.cuisine,
    this.theme = RecipeTheme.plain,
    this.accentColor,
    List<Diet>? diets,
    this.nutrition = Nutrition.empty,
    List<DraftIngredient>? ingredients,
    List<DraftStep>? steps,
    List<String>? tags,
  })  : diets = diets ?? <Diet>[],
        ingredients = ingredients ?? <DraftIngredient>[],
        steps = steps ?? <DraftStep>[],
        tags = tags ?? <String>[];

  final String? id;
  final List<Diet> diets;
  Nutrition nutrition;
  String title;
  String description;
  MealType mealType;
  Season season;
  int baseServings;
  int? prepMinutes;
  int? cookMinutes;
  String? externalVideoUrl;
  String? sourceUrl;
  bool isPublic;
  ImportSource importSource;
  Cuisine? cuisine;
  RecipeTheme theme;
  String? accentColor;
  final List<DraftIngredient> ingredients;
  final List<DraftStep> steps;
  final List<String> tags;

  bool get isEditing => id != null;

  /// A new object sharing no list with this one, so a notifier holding
  /// it sees a changed value and rebuilds its listeners.
  RecipeDraft snapshot() => RecipeDraft(
        id: id,
        title: title,
        description: description,
        mealType: mealType,
        season: season,
        baseServings: baseServings,
        prepMinutes: prepMinutes,
        cookMinutes: cookMinutes,
        externalVideoUrl: externalVideoUrl,
        sourceUrl: sourceUrl,
        isPublic: isPublic,
        importSource: importSource,
        cuisine: cuisine,
        theme: theme,
        accentColor: accentColor,
        diets: List<Diet>.of(diets),
        nutrition: nutrition,
        ingredients: List<DraftIngredient>.of(ingredients),
        steps: List<DraftStep>.of(steps),
        tags: List<String>.of(tags),
      );
}

class RecipeFilter {
  const RecipeFilter({
    this.mealType,
    this.season,
    this.query = '',
    this.tag,
    this.includePublic = false,
    this.cuisine,
    this.diets = const <Diet>[],
  });

  final List<Diet> diets;
  final Cuisine? cuisine;
  final MealType? mealType;
  final Season? season;
  final String query;
  final String? tag;
  final bool includePublic;

  bool get isActive =>
      mealType != null ||
      season != null ||
      query.isNotEmpty ||
      tag != null ||
      diets.isNotEmpty ||
      cuisine != null;

  RecipeFilter copyWith({
    MealType? mealType,
    Season? season,
    String? query,
    String? tag,
    bool? includePublic,
    Cuisine? cuisine,
    List<Diet>? diets,
    bool clearCuisine = false,
    bool clearMealType = false,
    bool clearSeason = false,
    bool clearTag = false,
  }) =>
      RecipeFilter(
        diets: diets ?? this.diets,
        mealType: clearMealType ? null : (mealType ?? this.mealType),
        season: clearSeason ? null : (season ?? this.season),
        query: query ?? this.query,
        tag: clearTag ? null : (tag ?? this.tag),
        includePublic: includePublic ?? this.includePublic,
        cuisine: clearCuisine ? null : (cuisine ?? this.cuisine),
      );
}

class RecipeRepository {
  RecipeRepository(this._client);

  final SupabaseClient _client;

  /// One round trip for the card grid. Ingredients and steps are left
  /// out here on purpose — pulling every step of every recipe to render
  /// a list of titles is the single easiest way to make this screen slow.
  static const String _listColumns =
      'id, library_id, title, description, meal_type, season, '
      'base_servings, prep_minutes, cook_minutes, cover_image_path, '
      'source_url, external_video_url, import_source, is_public, '
      'forked_from_recipe_id, created_at, cuisine, theme, accent_color, '
      'background_image_path, diets, calories, protein_g, carbs_g, fat_g, '
      'fiber_g, sugar_g, sodium_mg, '
      'recipe_tags(tags(name))';

  static const String _detailColumns = '$_listColumns, '
      'recipe_ingredients(id, ingredient_id, quantity, unit, note, is_optional, '
      'sort_order, ingredients(name, grocery_category)), '
      'recipe_steps(id, step_number, instruction, timer_seconds), '
      'recipe_images(id, storage_path, caption, sort_order)';

  Future<List<Recipe>> list({
    required String libraryId,
    RecipeFilter filter = const RecipeFilter(),
  }) async {
    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> builder =
          _client.from('recipes').select(_listColumns);

      // Even though RLS confines the result set, the tenant filter is
      // stated explicitly: it keeps the query on recipes_filter_idx and
      // it means a policy regression shows up as missing rows in tests
      // rather than as another library's recipes on screen.
      if (filter.includePublic) {
        // .or() takes a filter expression, so the id is shape-checked
        // before it is interpolated. .eq() below takes a bound value and
        // needs no such treatment.
        final String library =
            PostgrestSafe.requireUuid(libraryId, 'libraryId');
        builder = builder.or(
          'library_id.eq.$library,is_public.is.true',
        );
      } else {
        builder = builder.eq('library_id', libraryId);
      }

      if (filter.mealType != null) {
        builder = builder.eq('meal_type', filter.mealType!.wire);
      }
      if (filter.cuisine != null) {
        builder = builder.eq('cuisine', filter.cuisine!.wire);
      }
      if (filter.diets.isNotEmpty) {
        builder = builder.contains(
          'diets',
          filter.diets.map((Diet d) => d.wire).toList(),
        );
      }
      if (filter.season != null) {
        builder = builder.inFilter(
          'season',
          <String>[filter.season!.wire, Season.allYear.wire],
        );
      }
      if (filter.query.trim().isNotEmpty) {
        final String? pattern = PostgrestSafe.likePattern(
          InputSanitizer.singleLine(filter.query, maxLength: 60),
        );
        if (pattern != null) builder = builder.ilike('title', pattern);
      }

      final List<Map<String, dynamic>> rows =
          await builder.order('created_at', ascending: false).limit(200);

      final List<Recipe> recipes =
          rows.map(Recipe.fromJson).toList(growable: false);

      if (filter.tag == null) return recipes;
      return recipes
          .where((Recipe r) => r.tags
              .any((String t) => t.toLowerCase() == filter.tag!.toLowerCase()))
          .toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Public recipes from every library, newest first. Anonymous-safe:
  /// it relies on the public-recipe RLS policies and never filters by
  /// library. Tags are not embedded because tag rows are library-private.
  Future<List<Recipe>> feed({
    Cuisine? cuisine,
    MealType? mealType,
    List<Diet> diets = const <Diet>[],
    String query = '',
    int limit = 24,
    int offset = 0,
  }) async {
    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> builder =
          _client.from('recipes').select(_feedColumns).eq('is_public', true);
      if (diets.isNotEmpty) {
        builder = builder.contains(
          'diets',
          diets.map((Diet d) => d.wire).toList(),
        );
      }
      if (cuisine != null) builder = builder.eq('cuisine', cuisine.wire);
      if (mealType != null) builder = builder.eq('meal_type', mealType.wire);
      if (query.trim().isNotEmpty) {
        final String? pattern = PostgrestSafe.likePattern(
          InputSanitizer.singleLine(query, maxLength: 60),
        );
        if (pattern != null) builder = builder.ilike('title', pattern);
      }
      final List<Map<String, dynamic>> rows = await builder
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(Recipe.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  static const String _feedColumns =
      'id, library_id, title, description, meal_type, season, '
      'base_servings, prep_minutes, cook_minutes, cover_image_path, '
      'import_source, is_public, forked_from_recipe_id, created_at, '
      'cuisine, theme, accent_color, diets, calories, protein_g, carbs_g, '
      'fat_g, fiber_g, sugar_g, sodium_mg';

  Future<Recipe> byId(String recipeId) async {
    try {
      final Map<String, dynamic> row = await _client
          .from('recipes')
          .select(_detailColumns)
          .eq('id', recipeId)
          .single();
      return Recipe.fromJson(row);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Creates or updates a recipe together with its children.
  ///
  /// PostgREST has no multi-table transaction, so children are replaced
  /// with delete-then-insert. If the process dies between the two, the
  /// recipe is left without ingredients rather than with duplicated
  /// ones — recoverable by saving again. Moving this into a single
  /// plpgsql RPC would make it atomic; see README "Known trade-offs".
  Future<String> save({
    required RecipeDraft draft,
    required String libraryId,
  }) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) throw const Failure('Sign in first.', isAuth: true);

    final String title = InputSanitizer.singleLine(draft.title, maxLength: 160);
    if (title.isEmpty) throw const Failure('The recipe needs a title.');
    if (draft.ingredients.isEmpty) {
      throw const Failure('Add at least one ingredient.');
    }
    if (draft.steps.isEmpty) {
      throw const Failure('Add at least one step.');
    }

    final String? video = draft.externalVideoUrl == null
        ? null
        : InputSanitizer.videoUrl(draft.externalVideoUrl!);
    if (draft.externalVideoUrl != null &&
        draft.externalVideoUrl!.trim().isNotEmpty &&
        video == null) {
      throw const Failure(
        'That video link is not a supported https address.',
      );
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'library_id': libraryId,
      'title': title,
      'description':
          InputSanitizer.multiLine(draft.description, maxLength: 4000),
      'meal_type': draft.mealType.wire,
      'season': draft.season.wire,
      'base_servings': draft.baseServings.clamp(1, 100),
      'prep_minutes': draft.prepMinutes,
      'cook_minutes': draft.cookMinutes,
      'external_video_url': video,
      'source_url': draft.sourceUrl == null
          ? null
          : InputSanitizer.importUrl(draft.sourceUrl!),
      'import_source': draft.importSource.wire,
      'is_public': draft.isPublic,
      'cuisine': draft.cuisine?.wire,
      'theme': draft.theme.wire,
      'accent_color': draft.accentColor,
      'diets': draft.diets.map((Diet d) => d.wire).toSet().toList(),
      'calories': draft.nutrition.calories?.clamp(0, 5000),
      'protein_g': draft.nutrition.proteinG?.clamp(0, 500),
      'carbs_g': draft.nutrition.carbsG?.clamp(0, 500),
      'fat_g': draft.nutrition.fatG?.clamp(0, 500),
      'fiber_g': draft.nutrition.fiberG?.clamp(0, 500),
      'sugar_g': draft.nutrition.sugarG?.clamp(0, 500),
      'sodium_mg': draft.nutrition.sodiumMg?.clamp(0, 20000),
    };

    try {
      final String recipeId;
      if (draft.isEditing) {
        recipeId = draft.id!;
        await _client.from('recipes').update(payload).eq('id', recipeId);
        await _client
            .from('recipe_ingredients')
            .delete()
            .eq('recipe_id', recipeId);
        await _client.from('recipe_steps').delete().eq('recipe_id', recipeId);
      } else {
        payload['created_by'] = userId;
        final Map<String, dynamic> inserted =
            await _client.from('recipes').insert(payload).select('id').single();
        recipeId = inserted['id'] as String;
      }

      // library_id is sent for clarity, but the sync trigger in
      // migration 0003 overwrites it with the parent recipe's library.
      // Whatever the client sends here is not what gets stored.
      final List<Map<String, dynamic>> ingredientRows =
          <Map<String, dynamic>>[];
      for (int i = 0; i < draft.ingredients.length; i++) {
        final DraftIngredient item = draft.ingredients[i];
        ingredientRows.add(<String, dynamic>{
          'recipe_id': recipeId,
          'library_id': libraryId,
          'ingredient_id': item.ingredientId,
          'quantity': item.quantity,
          'unit': item.unit.wire,
          'note': item.note == null
              ? null
              : InputSanitizer.singleLine(item.note!, maxLength: 200),
          'is_optional': item.isOptional,
          'sort_order': i,
        });
      }

      final List<Map<String, dynamic>> stepRows = <Map<String, dynamic>>[];
      for (int i = 0; i < draft.steps.length; i++) {
        final DraftStep step = draft.steps[i];
        final String text =
            InputSanitizer.multiLine(step.instruction, maxLength: 2000);
        if (text.isEmpty) continue;
        stepRows.add(<String, dynamic>{
          'recipe_id': recipeId,
          'library_id': libraryId,
          'step_number': stepRows.length + 1,
          'instruction': text,
          'timer_seconds': step.timerSeconds,
        });
      }

      if (ingredientRows.isNotEmpty) {
        await _client.from('recipe_ingredients').insert(ingredientRows);
      }
      if (stepRows.isNotEmpty) {
        await _client.from('recipe_steps').insert(stepRows);
      }

      await _replaceTags(recipeId, libraryId, draft.tags);
      return recipeId;
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> _replaceTags(
    String recipeId,
    String libraryId,
    List<String> tags,
  ) async {
    await _client.from('recipe_tags').delete().eq('recipe_id', recipeId);
    if (tags.isEmpty) return;

    final List<String> clean = tags
        .map((String t) => InputSanitizer.singleLine(t, maxLength: 40))
        .where((String t) => t.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (clean.isEmpty) return;

    final List<Map<String, dynamic>> tagRows = await _client
        .from('tags')
        .upsert(
          clean
              .map((String name) => <String, dynamic>{
                    'library_id': libraryId,
                    'name': name,
                  })
              .toList(growable: false),
          onConflict: 'library_id,name',
          ignoreDuplicates: false,
        )
        .select('id');

    await _client.from('recipe_tags').insert(
          tagRows
              .map((Map<String, dynamic> t) => <String, dynamic>{
                    'recipe_id': recipeId,
                    'tag_id': t['id'],
                    'library_id': libraryId,
                  })
              .toList(growable: false),
        );
  }

  Future<void> delete(String recipeId) async {
    try {
      await _client.from('recipes').delete().eq('id', recipeId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> setPublic(String recipeId, bool isPublic) async {
    try {
      await _client
          .from('recipes')
          .update(<String, dynamic>{'is_public': isPublic}).eq('id', recipeId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Text-only fork. The server function does the copying so that the
  /// visibility check and the insert cannot drift apart.
  Future<String> fork({
    required String recipeId,
    required String libraryId,
  }) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'fork_recipe',
        params: <String, dynamic>{
          'p_recipe_id': recipeId,
          'p_library_id': libraryId,
        },
      );
      return result as String;
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Anonymous cook-time analytics. No user column exists on the table.
  Future<void> logCookTime({
    required String recipeId,
    required int minutes,
  }) async {
    if (minutes < 1 || minutes > 1440) return;
    try {
      await _client.from('cook_logs').insert(<String, dynamic>{
        'recipe_id': recipeId,
        'cook_minutes': minutes,
      });
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<int?> averageCookMinutes(String recipeId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('recipe_cook_time_stats')
          .select('avg_cook_minutes, sample_count')
          .eq('recipe_id', recipeId)
          .limit(1);
      if (rows.isEmpty) return null;
      final Object? count = rows.first['sample_count'];
      if (count is int && count < 3) return null; // too few to be meaningful
      final Object? avg = rows.first['avg_cook_minutes'];
      return avg is int ? avg : null;
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
