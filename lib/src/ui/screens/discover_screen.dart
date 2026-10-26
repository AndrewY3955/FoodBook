import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../state/discover_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';
import '../widgets/category_slider.dart';
import '../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';

/// Public recipes from everyone, browsable by meal and cuisine.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DiscoverFilter filter = ref.watch(discoverFilterProvider);
    final DiscoverController controller =
        ref.read(discoverFilterProvider.notifier);
    final AsyncValue<List<Recipe>> feed = ref.watch(discoverFeedProvider);

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Search shared recipes',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        suffixIcon: filter.query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  controller.setQuery('');
                                },
                              ),
                      ),
                      onChanged: controller.setQuery,
                    ),
                    const SizedBox(height: 6),
                    CategorySlider<MealType>(
                      semanticsLabel: 'Meal type',
                      selected: filter.mealType,
                      onChanged: controller.setMealType,
                      options: <CategoryOption<MealType>>[
                        for (final MealType m in MealType.values)
                          CategoryOption<MealType>(
                            value: m,
                            label: m.label,
                            emoji: m.emoji,
                          ),
                      ],
                    ),
                    CategorySlider<Cuisine>(
                      semanticsLabel: 'Cuisine',
                      selected: filter.cuisine,
                      onChanged: controller.setCuisine,
                      options: <CategoryOption<Cuisine>>[
                        for (final Cuisine c in Cuisine.values)
                          CategoryOption<Cuisine>(
                            value: c,
                            label: c.label,
                            emoji: c.emoji,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: feed.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace s) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.cloud_off, size: 40),
                      const SizedBox(height: 12),
                      const Text('Could not load shared recipes.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(discoverFeedProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (List<Recipe> list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.explore_outlined, size: 44),
                            const SizedBox(height: 14),
                            Text(
                              filter.isActive
                                  ? 'Nothing shared matches that yet.'
                                  : 'No shared recipes yet.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              filter.isActive
                                  ? 'Try another category.'
                                  : 'Share one of yours and it will show up here.',
                              textAlign: TextAlign.center,
                            ),
                            if (filter.isActive) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () {
                                  _search.clear();
                                  controller.clear();
                                },
                                child: const Text('Clear filters'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  // A full window means there may be more behind it.
                  final bool mayHaveMore = list.length >= filter.limit;

                  return ContentWidth(
                    child: RefreshIndicator(
                      onRefresh: () async => ref.invalidate(discoverFeedProvider),
                      child: CustomScrollView(
                        slivers: <Widget>[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    Breakpoints.recipeColumns(scope.width),
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.82,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (BuildContext context, int i) {
                                  final Recipe recipe = list[i];
                                  return RecipeCard(
                                    recipe: recipe,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => RecipeDetailScreen(
                                            recipeId: recipe.id),
                                      ),
                                    ),
                                  );
                                },
                                childCount: list.length,
                              ),
                            ),
                          ),
                          if (mayHaveMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    16, 4, 16, scope.isPhone ? 96 : 24),
                                child: Center(
                                  child: OutlinedButton(
                                    onPressed: controller.loadMore,
                                    child: const Text('Load more'),
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverToBoxAdapter(
                              child: SizedBox(height: scope.isPhone ? 96 : 24),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
