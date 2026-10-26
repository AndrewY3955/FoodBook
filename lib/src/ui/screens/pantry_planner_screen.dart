import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quantity_format.dart';
import '../../core/security/input_sanitizer.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../state/meal_plan_controller.dart';
import '../../state/pantry_controllers.dart';
import '../../state/recipe_controllers.dart';
import '../responsive/breakpoints.dart';
import 'recipe_detail_screen.dart';

/// Planner and pantry.
///
///   phone    two tabs
///   tablet   planner above, pantry below
///   desktop  wide horizontal calendar beside the pantry column
class PantryPlannerScreen extends ConsumerWidget {
  const PantryPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        if (scope.isPhone) {
          return const DefaultTabController(
            length: 2,
            child: Column(
              children: <Widget>[
                TabBar(
                  tabs: <Widget>[
                    Tab(text: 'This week'),
                    Tab(text: 'Pantry'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _PlannerPane(),
                      _PantryPane(),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        if (scope.isTablet) {
          return const Column(
            children: <Widget>[
              Expanded(flex: 5, child: _PlannerPane()),
              Divider(height: 1),
              Expanded(flex: 4, child: _PantryPane()),
            ],
          );
        }

        return const Row(
          children: <Widget>[
            Expanded(flex: 7, child: _PlannerPane()),
            VerticalDivider(width: 1),
            Expanded(flex: 4, child: _PantryPane()),
          ],
        );
      },
    );
  }
}

class _PlannerPane extends ConsumerWidget {
  const _PlannerPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlannerWeek week = ref.watch(plannerWeekProvider);
    final PlannerWeekController weekController =
        ref.read(plannerWeekProvider.notifier);
    final Map<String, Map<MealType, List<MealPlanEntry>>> grid =
        ref.watch(plannerGridProvider);
    final AsyncValue<List<MealPlanEntry>> entries = ref.watch(mealPlanProvider);

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        final Widget header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: weekController.previous,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _weekLabel(week),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: weekController.next,
              ),
              TextButton(
                onPressed: weekController.thisWeek,
                child: const Text('Today'),
              ),
            ],
          ),
        );

        final Widget body = entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace s) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(mealPlanProvider),
              child: const Text('Retry'),
            ),
          ),
          data: (_) {
            // Desktop gets the expansive horizontal grid the brief asks
            // for: seven day columns across, meals down.
            if (scope.isDesktop) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final DateTime day in week.days)
                        SizedBox(
                          width: 210,
                          child: _DayColumn(
                            day: day,
                            byMeal: grid[dayKey(day)] ??
                                const <MealType, List<MealPlanEntry>>{},
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: <Widget>[
                for (final DateTime day in week.days)
                  _DayColumn(
                    day: day,
                    byMeal: grid[dayKey(day)] ??
                        const <MealType, List<MealPlanEntry>>{},
                  ),
              ],
            );
          },
        );

        return Column(
          children: <Widget>[header, Expanded(child: body)],
        );
      },
    );
  }

  static String _weekLabel(PlannerWeek week) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final DateTime a = week.start;
    final DateTime b = week.end;
    if (a.month == b.month) {
      return '${a.day}–${b.day} ${months[a.month - 1]}';
    }
    return '${a.day} ${months[a.month - 1]} – ${b.day} ${months[b.month - 1]}';
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({required this.day, required this.byMeal});

  final DateTime day;
  final Map<MealType, List<MealPlanEntry>> byMeal;

  static const List<String> _weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final bool isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    return Card(
      margin: const EdgeInsets.all(6),
      color: isToday ? theme.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${_weekdays[day.weekday - 1]} ${day.day}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            for (final MealType meal in MealType.values)
              if ((byMeal[meal] ?? const <MealPlanEntry>[]).isNotEmpty)
                for (final MealPlanEntry entry in byMeal[meal]!)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.recipeTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(meal.label),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RecipeDetailScreen(recipeId: entry.recipeId),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          ref.read(mealPlanProvider.notifier).remove(entry.id),
                    ),
                  ),
            TextButton.icon(
              onPressed: () => _planSomething(context, ref, day),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Plan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _planSomething(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
  ) async {
    final List<Recipe> recipes =
        ref.read(recipeListProvider).valueOrNull ?? const <Recipe>[];
    if (recipes.isEmpty) return;

    MealType meal = MealType.dinner;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<MealType>(
                  segments: MealType.values
                      .map((MealType m) => ButtonSegment<MealType>(
                            value: m,
                            label: Text(m.label),
                          ))
                      .toList(growable: false),
                  selected: <MealType>{meal},
                  onSelectionChanged: (Set<MealType> s) =>
                      setSheetState(() => meal = s.first),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: recipes.length,
                  itemBuilder: (BuildContext context, int i) => ListTile(
                    title: Text(recipes[i].title),
                    subtitle: Text(recipes[i].mealType.label),
                    onTap: () async {
                      await ref.read(mealPlanProvider.notifier).add(
                            recipeId: recipes[i].id,
                            date: day,
                            mealType: meal,
                          );
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PantryPane extends ConsumerWidget {
  const _PantryPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PantryMatch>> matches =
        ref.watch(pantryMatchProvider);
    final Map<GroceryCategory, List<PantryItem>> pantry =
        ref.watch(pantryByCategoryProvider);
    final int threshold = ref.watch(matchThresholdProvider);
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: <Widget>[
        Text('What can I cook?', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(
              child: Slider(
                value: threshold.toDouble(),
                max: 100,
                divisions: 10,
                label: '$threshold%',
                onChanged: (double v) =>
                    ref.read(matchThresholdProvider.notifier).set(v.round()),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                'at least $threshold%',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        matches.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, StackTrace s) =>
              const Text('Could not work that out just now.'),
          data: (List<PantryMatch> list) {
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Nothing clears that bar yet. Lower it, or add what is '
                  'already in your cupboard below.',
                ),
              );
            }
            return Column(
              children: <Widget>[
                for (final PantryMatch m in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: m.isCookable
                          ? Colors.green.shade700
                          : theme.colorScheme.secondaryContainer,
                      child: Text(
                        '${m.matchPct}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: m.isCookable
                              ? Colors.white
                              : theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    title: Text(m.title),
                    subtitle: Text(
                      m.isCookable
                          ? 'You have everything'
                          : 'Missing ${m.missingCount} of ${m.requiredCount}',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RecipeDetailScreen(recipeId: m.recipeId),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const Divider(height: 32),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('In the cupboard', style: theme.textTheme.titleLarge),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _addToPantry(context, ref),
            ),
          ],
        ),
        if (pantry.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Add a few staples and the suggestions above get useful fast.',
            ),
          ),
        for (final GroceryCategory c in pantry.keys)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: Text(
                  c.label.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final PantryItem item in pantry[c]!)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle:
                      Text(QuantityFormat.withUnit(item.quantity, item.unit)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => ref
                        .read(pantryControllerProvider.notifier)
                        .remove(item.id),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _addToPantry(BuildContext context, WidgetRef ref) async {
    final TextEditingController search = TextEditingController();
    final TextEditingController quantity = TextEditingController(text: '1');
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: search,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Ingredient',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (String v) => setSheetState(() => query = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: quantity,
                        decoration: const InputDecoration(labelText: 'Qty'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: Consumer(
                    builder: (BuildContext context, WidgetRef ref, _) {
                      final AsyncValue<List<Ingredient>> results =
                          ref.watch(ingredientSearchProvider(query));
                      return results.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => const Center(
                          child: Text('Search failed.'),
                        ),
                        data: (List<Ingredient> list) => ListView(
                          children: <Widget>[
                            for (final Ingredient i in list)
                              ListTile(
                                dense: true,
                                title: Text(i.name),
                                subtitle: Text(i.category.label),
                                onTap: () async {
                                  final double amount =
                                      InputSanitizer.quantity(quantity.text) ??
                                          1;
                                  await ref
                                      .read(pantryControllerProvider.notifier)
                                      .upsert(
                                        ingredientId: i.id,
                                        quantity: amount,
                                        unit: i.defaultUnit,
                                      );
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    search.dispose();
    quantity.dispose();
  }
}
