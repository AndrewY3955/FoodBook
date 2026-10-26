import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import '../data/repositories/recipe_repository.dart';
import 'library_controller.dart';
import 'discover_controller.dart';
import 'providers.dart';

/// Current filter for the recipe box. Held separately from the list so
/// that changing a chip does not rebuild the repository provider.
class RecipeFilterController extends Notifier<RecipeFilter> {
  @override
  RecipeFilter build() => const RecipeFilter();

  void setMealType(MealType? value) {
    state = value == null
        ? state.copyWith(clearMealType: true)
        : state.copyWith(mealType: value);
  }

  void setSeason(Season? value) {
    state = value == null
        ? state.copyWith(clearSeason: true)
        : state.copyWith(season: value);
  }

  void setTag(String? value) {
    state = value == null
        ? state.copyWith(clearTag: true)
        : state.copyWith(tag: value);
  }

  void setQuery(String value) => state = state.copyWith(query: value);

  void toggleDiet(Diet diet) {
    final List<Diet> next = List<Diet>.of(state.diets);
    next.contains(diet) ? next.remove(diet) : next.add(diet);
    state = state.copyWith(diets: next);
  }

  void setCuisine(Cuisine? value) {
    state = value == null
        ? state.copyWith(clearCuisine: true)
        : state.copyWith(cuisine: value);
  }

  /// Handy shortcut on the seasonal chip: pick whatever season it is
  /// where the user is standing.
  void applyCurrentSeason(DateTime now) {
    const Map<int, Season> byMonth = <int, Season>{
      1: Season.winter,
      2: Season.winter,
      3: Season.spring,
      4: Season.spring,
      5: Season.spring,
      6: Season.summer,
      7: Season.summer,
      8: Season.summer,
      9: Season.autumn,
      10: Season.autumn,
      11: Season.autumn,
      12: Season.winter,
    };
    setSeason(byMonth[now.month] ?? Season.allYear);
  }

  void clear() => state = const RecipeFilter();
}

final NotifierProvider<RecipeFilterController, RecipeFilter>
    recipeFilterProvider =
    NotifierProvider<RecipeFilterController, RecipeFilter>(
        RecipeFilterController.new);

/// The recipe box. Rebuilds when the library or the filter changes.
final FutureProvider<List<Recipe>> recipeListProvider =
    FutureProvider<List<Recipe>>((Ref ref) async {
  final String? libraryId = ref.watch(activeLibraryIdProvider);
  if (libraryId == null) return const <Recipe>[];
  final RecipeFilter filter = ref.watch(recipeFilterProvider);
  return ref
      .watch(recipeRepositoryProvider)
      .list(libraryId: libraryId, filter: filter);
});

final FutureProviderFamily<Recipe, String> recipeDetailProvider =
    FutureProvider.family<Recipe, String>(
  (Ref ref, String recipeId) =>
      ref.watch(recipeRepositoryProvider).byId(recipeId),
);

final FutureProviderFamily<int?, String> averageCookMinutesProvider =
    FutureProvider.family<int?, String>(
  (Ref ref, String recipeId) =>
      ref.watch(recipeRepositoryProvider).averageCookMinutes(recipeId),
);

/// All tags in use in this library, derived from the loaded list rather
/// than fetched again.
final Provider<List<String>> libraryTagsProvider =
    Provider<List<String>>((Ref ref) {
  return ref.watch(recipeListProvider).maybeWhen(
        data: (List<Recipe> recipes) {
          final Set<String> tags = <String>{};
          for (final Recipe r in recipes) {
            tags.addAll(r.tags);
          }
          final List<String> sorted = tags.toList()
            ..sort((String a, String b) =>
                a.toLowerCase().compareTo(b.toLowerCase()));
          return sorted;
        },
        orElse: () => const <String>[],
      );
});

/// How many servings the detail screen is currently showing. Keyed by
/// recipe id so two open recipes do not share a scale.
class ServingsController extends FamilyNotifier<int, String> {
  @override
  int build(String recipeId) {
    return ref.watch(recipeDetailProvider(recipeId)).maybeWhen(
          data: (Recipe r) => r.baseServings,
          orElse: () => 4,
        );
  }

  void set(int value) => state = value.clamp(1, 100);

  void increment() => set(state + 1);

  void decrement() => set(state - 1);
}

final NotifierProviderFamily<ServingsController, int, String> servingsProvider =
    NotifierProvider.family<ServingsController, int, String>(
        ServingsController.new);

/// Create / edit. Holds a mutable draft; the widgets mutate it through
/// these methods so that every change funnels through one setState.
class RecipeFormController extends Notifier<RecipeDraft> {
  @override
  RecipeDraft build() => RecipeDraft();

  void reset() => state = RecipeDraft();

  void loadFrom(Recipe recipe) {
    state = RecipeDraft(
      id: recipe.id,
      title: recipe.title,
      description: recipe.description ?? '',
      mealType: recipe.mealType,
      season: recipe.season,
      baseServings: recipe.baseServings,
      prepMinutes: recipe.prepMinutes,
      cookMinutes: recipe.cookMinutes,
      externalVideoUrl: recipe.externalVideoUrl,
      sourceUrl: recipe.sourceUrl,
      isPublic: recipe.isPublic,
      importSource: recipe.importSource,
      cuisine: recipe.cuisine,
      theme: recipe.theme,
      accentColor: recipe.accentColor,
      diets: List<Diet>.of(recipe.diets),
      nutrition: recipe.nutrition,
      ingredients: recipe.sortedIngredients
          .map((RecipeIngredient i) => DraftIngredient(
                ingredientId: i.ingredientId,
                name: i.name,
                quantity: i.quantity,
                unit: i.unit,
                note: i.note,
                isOptional: i.isOptional,
              ))
          .toList(),
      steps: recipe.sortedSteps
          .map((RecipeStep s) => DraftStep(
                instruction: s.instruction,
                timerSeconds: s.timerSeconds,
              ))
          .toList(),
      tags: List<String>.of(recipe.tags),
    );
  }

  /// Seeds the form from a parsed import. Nothing is saved yet — the
  /// user reviews and corrects first, which is the only realistic way
  /// to handle text scraped from a social caption.
  void loadFromImport(ParsedImport parsed, List<DraftIngredient> matched) {
    state = RecipeDraft(
      title: parsed.title,
      description: parsed.description ?? '',
      baseServings: parsed.servings ?? 4,
      sourceUrl: parsed.sourceUrl,
      externalVideoUrl: parsed.sourceUrl,
      importSource: parsed.source,
      ingredients: matched,
      steps: parsed.stepLines
          .map((String line) => DraftStep(instruction: line))
          .toList(),
    );
  }

  void _touch() => state = state.snapshot();

  void setCuisine(Cuisine? value) {
    state.cuisine = value;
    _touch();
  }

  void toggleDiet(Diet diet) {
    state.diets.contains(diet)
        ? state.diets.remove(diet)
        : state.diets.add(diet);
    _touch();
  }

  void setNutrition(Nutrition value) {
    state.nutrition = value;
    _touch();
  }

  void setTheme(RecipeTheme value) {
    state.theme = value;
    _touch();
  }

  void setAccentColor(String? value) {
    state.accentColor = value;
    _touch();
  }

  void setTitle(String value) {
    state.title = value;
    _touch();
  }

  void setDescription(String value) {
    state.description = value;
    _touch();
  }

  void setMealType(MealType value) {
    state.mealType = value;
    _touch();
  }

  void setSeason(Season value) {
    state.season = value;
    _touch();
  }

  void setBaseServings(int value) {
    state.baseServings = value.clamp(1, 100);
    _touch();
  }

  void setPrepMinutes(int? value) {
    state.prepMinutes = value;
    _touch();
  }

  void setCookMinutes(int? value) {
    state.cookMinutes = value;
    _touch();
  }

  void setVideoUrl(String? value) {
    state.externalVideoUrl = value;
    _touch();
  }

  void setPublic(bool value) {
    state.isPublic = value;
    _touch();
  }

  void addIngredient(DraftIngredient item) {
    state.ingredients.add(item);
    _touch();
  }

  void updateIngredient(int index, DraftIngredient item) {
    if (index < 0 || index >= state.ingredients.length) return;
    state.ingredients[index] = item;
    _touch();
  }

  void removeIngredient(int index) {
    if (index < 0 || index >= state.ingredients.length) return;
    state.ingredients.removeAt(index);
    _touch();
  }

  void addStep([String text = '']) {
    state.steps.add(DraftStep(instruction: text));
    _touch();
  }

  void updateStep(int index, String instruction, int? timerSeconds) {
    if (index < 0 || index >= state.steps.length) return;
    state.steps[index]
      ..instruction = instruction
      ..timerSeconds = timerSeconds;
    _touch();
  }

  void removeStep(int index) {
    if (index < 0 || index >= state.steps.length) return;
    state.steps.removeAt(index);
    _touch();
  }

  Future<String> save() async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) {
      throw StateError('No library selected.');
    }
    final String recipeId = await ref
        .read(recipeRepositoryProvider)
        .save(draft: state, libraryId: libraryId);

    ref.invalidate(recipeListProvider);
    ref.invalidate(discoverFeedProvider);
    ref.invalidate(recipeDetailProvider(recipeId));
    return recipeId;
  }
}

final NotifierProvider<RecipeFormController, RecipeDraft> recipeFormProvider =
    NotifierProvider<RecipeFormController, RecipeDraft>(
        RecipeFormController.new);
