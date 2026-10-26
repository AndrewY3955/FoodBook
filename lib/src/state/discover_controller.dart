import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import 'providers.dart';

class DiscoverFilter {
  const DiscoverFilter({
    this.cuisine,
    this.mealType,
    this.query = '',
    this.limit = pageSize,
  });

  static const int pageSize = 24;

  final Cuisine? cuisine;
  final MealType? mealType;
  final String query;
  final int limit;

  bool get isActive => cuisine != null || mealType != null || query.isNotEmpty;

  /// Changing a category or the query starts again from the first page.
  DiscoverFilter copyWith({
    Cuisine? cuisine,
    MealType? mealType,
    String? query,
    int? limit,
    bool clearCuisine = false,
    bool clearMealType = false,
  }) =>
      DiscoverFilter(
        cuisine: clearCuisine ? null : (cuisine ?? this.cuisine),
        mealType: clearMealType ? null : (mealType ?? this.mealType),
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
        query: state.query,
      );

  void setMealType(MealType? value) => state = DiscoverFilter(
        cuisine: state.cuisine,
        mealType: value,
        query: state.query,
      );

  void setQuery(String value) => state = DiscoverFilter(
        cuisine: state.cuisine,
        mealType: state.mealType,
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
        query: filter.query,
        limit: filter.limit,
      );
});
