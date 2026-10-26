import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import 'providers.dart';

class DiscoverFilter {
  const DiscoverFilter({
    this.cuisine,
    this.mealType,
    this.diets = const <Diet>[],
    this.query = '',
    this.limit = pageSize,
  });

  static const int pageSize = 24;

  final Cuisine? cuisine;
  final MealType? mealType;
  final List<Diet> diets;
  final String query;
  final int limit;

  bool get isActive =>
      cuisine != null ||
      mealType != null ||
      diets.isNotEmpty ||
      query.isNotEmpty;

  /// Changing a category or the query starts again from the first page.
  DiscoverFilter copyWith({
    Cuisine? cuisine,
    MealType? mealType,
    List<Diet>? diets,
    String? query,
    int? limit,
    bool clearCuisine = false,
    bool clearMealType = false,
  }) =>
      DiscoverFilter(
        cuisine: clearCuisine ? null : (cuisine ?? this.cuisine),
        mealType: clearMealType ? null : (mealType ?? this.mealType),
        diets: diets ?? this.diets,
        query: query ?? this.query,
        limit: limit ?? this.limit,
      );
}

class DiscoverController extends Notifier<DiscoverFilter> {
  @override
  DiscoverFilter build() => const DiscoverFilter();

  void setCuisine(Cuisine? value) => state = DiscoverFilter(
        cuisine: value,
        mealType: state.mealType,
        diets: state.diets,
        query: state.query,
      );

  void setMealType(MealType? value) => state = DiscoverFilter(
        cuisine: state.cuisine,
        mealType: value,
        diets: state.diets,
        query: state.query,
      );

  void toggleDiet(Diet diet) {
    final List<Diet> next = List<Diet>.of(state.diets);
    next.contains(diet) ? next.remove(diet) : next.add(diet);
    state = DiscoverFilter(
      cuisine: state.cuisine,
      mealType: state.mealType,
      diets: next,
      query: state.query,
    );
  }

  void setQuery(String value) => state = DiscoverFilter(
        cuisine: state.cuisine,
        mealType: state.mealType,
        diets: state.diets,
        query: value,
      );

  void loadMore() =>
      state = state.copyWith(limit: state.limit + DiscoverFilter.pageSize);

  void clear() => state = const DiscoverFilter();
}

final NotifierProvider<DiscoverController, DiscoverFilter>
    discoverFilterProvider =
    NotifierProvider<DiscoverController, DiscoverFilter>(
        DiscoverController.new);

/// Public recipes matching the discovery filter. The limit grows with
/// "Load more", which refetches the whole window; at the page sizes in
/// play that is cheaper than the bookkeeping of merging pages.
final FutureProvider<List<Recipe>> discoverFeedProvider =
    FutureProvider<List<Recipe>>((Ref ref) {
  final DiscoverFilter filter = ref.watch(discoverFilterProvider);
  return ref.watch(recipeRepositoryProvider).feed(
        cuisine: filter.cuisine,
        mealType: filter.mealType,
        diets: filter.diets,
        query: filter.query,
        limit: filter.limit,
      );
});
