import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../state/recipe_controllers.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';
import '../widgets/category_slider.dart';
import '../widgets/diet_chips.dart';
import '../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';

/// null = automatic: List on phones (largest text, one column), Grid
/// elsewhere. Once the user picks, their choice wins on every screen size.
class RecipeViewModeController extends Notifier<bool?> {
  @override
  bool? build() => null;

  // ignore: use_setters_to_change_properties
  void set(bool grid) => state = grid;
}

final NotifierProvider<RecipeViewModeController, bool?>
    recipeGridModeProvider =
    NotifierProvider<RecipeViewModeController, bool?>(
  RecipeViewModeController.new,
);

/// The recipe box: search, one Filter button, and a Grid or List.
///
/// Columns come from the width of this pane, not the window, so the
/// grid reflows correctly when the desktop sidebar is present.
class RecipeBoxScreen extends ConsumerWidget {
  const RecipeBoxScreen({super.key});

  void _open(BuildContext context, Recipe recipe) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(recipeId: recipe.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recipe>> recipes = ref.watch(recipeListProvider);
    final bool? gridChoice = ref.watch(recipeGridModeProvider);

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        final bool grid = gridChoice ?? !scope.isPhone;
        final bool hasRecipes = recipes.asData?.value.isNotEmpty ?? false;

        return Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                _FilterBar(grid: grid),
                Expanded(
                  child: recipes.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object e, StackTrace s) => _ErrorState(
                      onRetry: () => ref.invalidate(recipeListProvider),
                    ),
                    data: (List<Recipe> list) {
                      if (list.isEmpty) return const _EmptyState();

                      const EdgeInsets padding = EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        // Room for the Add recipe button so it never
                        // covers the last card.
                        88,
                      );

                      return ContentWidth(
                        child: RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(recipeListProvider),
                          child: grid
                              ? GridView.builder(
                                  padding: padding,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: Breakpoints.recipeColumns(
                                      scope.width,
                                    ).clamp(2, 5),
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 0.78,
                                  ),
                                  itemCount: list.length,
                                  itemBuilder: (BuildContext context, int i) =>
                                      RecipeCard(
                                    recipe: list[i],
                                    onTap: () => _open(context, list[i]),
                                  ),
                                )
                              : ListView.separated(
                                  padding: padding,
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (BuildContext context, int i) =>
                                      RecipeListTile(
                                    recipe: list[i],
                                    onTap: () => _open(context, list[i]),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (hasRecipes)
              const Positioned(
                right: 16,
                bottom: 16,
                child: _AddButton(),
              ),
          ],
        );
      },
    );
  }
}

/// Importing from a link is paused until it ships as a feature; see
/// import_screen.dart, which is kept but no longer reachable.
class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RecipeFormScreen()),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add recipe'),
    );
  }
}

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar({required this.grid});

  final bool grid;

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _FilterSheet(onClear: _search.clear),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    final RecipeFilterController controller =
        ref.read(recipeFilterProvider.notifier);
    final int active = (filter.mealType != null ? 1 : 0) +
        (filter.cuisine != null ? 1 : 0) +
        filter.diets.length +
        (filter.season != null ? 1 : 0) +
        (filter.tag != null ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your recipes',
                prefixIcon: const Icon(Icons.search),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune),
                  label: Text(active > 0 ? 'Filter ($active)' : 'Filter'),
                ),
                if (filter.isActive)
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      controller.clear();
                    },
                    child: const Text('Clear all'),
                  ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.grid_view),
                      label: Text('Grid'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.view_list),
                      label: Text('List'),
                    ),
                  ],
                  selected: <bool>{widget.grid},
                  onSelectionChanged: (Set<bool> v) => ref
                      .read(recipeGridModeProvider.notifier)
                      .set(v.first),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    final RecipeFilterController controller =
        ref.read(recipeFilterProvider.notifier);
    final List<String> tags = ref.watch(libraryTagsProvider);
    final ThemeData theme = Theme.of(context);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(text, style: theme.textTheme.titleMedium),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ContentWidth(
          maxWidth: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Filter recipes',
                        style: theme.textTheme.titleLarge),
                  ),
                  if (filter.isActive)
                    TextButton(
                      onPressed: () {
                        onClear();
                        controller.clear();
                      },
                      child: const Text('Clear all'),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
              heading('Meal'),
              CategorySlider<MealType>(
                semanticsLabel: 'Meal type',
                selected: filter.mealType,
                onChanged: controller.setMealType,
                options: <CategoryOption<MealType>>[
                  for (final MealType meal in MealType.values)
                    CategoryOption<MealType>(
                      value: meal,
                      label: meal.label,
                      emoji: meal.emoji,
                    ),
                ],
              ),
              heading('Cuisine'),
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
              heading('Diet'),
              DietChips(
                selected: filter.diets,
                onToggle: controller.toggleDiet,
              ),
              heading('Season'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Season season in Season.values)
                    if (season != Season.allYear)
                      FilterChip(
                        label: Text(season.label),
                        selected: filter.season == season,
                        onSelected: (bool on) =>
                            controller.setSeason(on ? season : null),
                      ),
                  ActionChip(
                    avatar: const Icon(Icons.eco_outlined, size: 18),
                    label: const Text('In season now'),
                    onPressed: () =>
                        controller.applyCurrentSeason(DateTime.now()),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...<Widget>[
                heading('Tags'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String tag in tags)
                      FilterChip(
                        label: Text(tag),
                        selected:
                            filter.tag?.toLowerCase() == tag.toLowerCase(),
                        onSelected: (bool on) =>
                            controller.setTag(on ? tag : null),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool filtered = ref.watch(recipeFilterProvider).isActive;
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              filtered
                  ? 'Nothing matches those filters.'
                  : 'No recipes here yet.',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Try clearing one of them.'
                  : 'Write down your first one to get started.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (filtered)
              OutlinedButton(
                onPressed: ref.read(recipeFilterProvider.notifier).clear,
                child: const Text('Clear filters'),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecipeFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add recipe'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            const Text('Could not load your recipes.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
