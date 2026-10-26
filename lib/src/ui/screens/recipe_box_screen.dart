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
import 'import_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';

/// The recipe box: filter rail plus a responsive grid.
///
/// Columns come from the width of this pane, not the window, so the
/// grid reflows correctly when the desktop sidebar is present.
class RecipeBoxScreen extends ConsumerWidget {
  const RecipeBoxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recipe>> recipes = ref.watch(recipeListProvider);

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        return Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                const _FilterBar(),
                Expanded(
                  child: recipes.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object e, StackTrace s) => _ErrorState(
                      onRetry: () => ref.invalidate(recipeListProvider),
                    ),
                    data: (List<Recipe> list) {
                      if (list.isEmpty) return const _EmptyState();

                      return ContentWidth(
                        child: RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(recipeListProvider),
                          child: GridView.builder(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              scope.isPhone ? 96 : 24,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  Breakpoints.recipeColumns(scope.width),
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.82,
                            ),
                            itemCount: list.length,
                            itemBuilder: (BuildContext context, int i) {
                              final Recipe recipe = list[i];
                              return RecipeCard(
                                recipe: recipe,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        RecipeDetailScreen(recipeId: recipe.id),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: _AddMenu(),
            ),
          ],
        );
      },
    );
  }
}

class _AddMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Add a recipe',
      onSelected: (String value) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => value == 'import'
                ? const ImportScreen()
                : const RecipeFormScreen(),
          ),
        );
      },
      itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'manual',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Write it out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'import',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Paste a link'),
            subtitle: Text('Instagram, TikTok or the web'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: const FloatingActionButton.extended(
        // The FAB is decorative here; the popup owns the tap.
        onPressed: null,
        icon: Icon(Icons.add),
        label: Text('Add recipe'),
      ),
    );
  }
}

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final TextEditingController _search = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    final int extraActive = (filter.cuisine != null ? 1 : 0) +
        filter.diets.length +
        (filter.season != null ? 1 : 0) +
        (filter.tag != null ? 1 : 0);
    final RecipeFilterController controller =
        ref.read(recipeFilterProvider.notifier);
    final List<String> tags = ref.watch(libraryTagsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search your recipes',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
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
                for (final MealType meal in MealType.values)
                  CategoryOption<MealType>(
                    value: meal,
                    label: meal.label,
                    emoji: meal.emoji,
                  ),
              ],
            ),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.tune,
                    size: 18,
                  ),
                  label: Text(
                    _expanded
                        ? 'Fewer filters'
                        : extraActive > 0
                            ? 'More filters ($extraActive)'
                            : 'More filters',
                  ),
                ),
                if (filter.isActive)
                  TextButton.icon(
                    onPressed: () {
                      _search.clear();
                      controller.clear();
                    },
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            if (_expanded) ...<Widget>[
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
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DietChips(
                  selected: filter.diets,
                  onToggle: controller.toggleDiet,
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final Season season in Season.values)
                      if (season != Season.allYear)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(season.label),
                            selected: filter.season == season,
                            onSelected: (bool on) =>
                                controller.setSeason(on ? season : null),
                          ),
                        ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.eco_outlined, size: 16),
                      label: const Text('In season now'),
                      onPressed: () =>
                          controller.applyCurrentSeason(DateTime.now()),
                    ),
                    if (tags.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 6),
                      const _Separator(),
                      const SizedBox(width: 6),
                      for (final String tag in tags)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(tag),
                            selected:
                                filter.tag?.toLowerCase() == tag.toLowerCase(),
                            onSelected: (bool on) =>
                                controller.setTag(on ? tag : null),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      );
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool filtered = ref.watch(recipeFilterProvider).isActive;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.menu_book_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              filtered
                  ? 'Nothing matches those filters.'
                  : 'No recipes here yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try clearing one of them.'
                  : 'Write one out, or paste a link to one you saw.',
              textAlign: TextAlign.center,
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
