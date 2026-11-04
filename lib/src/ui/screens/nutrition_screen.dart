import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../data/models/models.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../state/nutrition_controllers.dart';
import '../../state/recipe_controllers.dart';
import '../widgets/nutrition_widgets.dart';

DateTime _today() {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _guessMeal() {
  final int h = DateTime.now().hour;
  if (h < 10) return 'breakfast';
  if (h < 15) return 'lunch';
  if (h < 21) return 'dinner';
  return 'snack';
}

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

/// Asks for meal and servings, then adds the recipe to today's diary.
Future<void> logRecipeToDiary(
  BuildContext context,
  WidgetRef ref,
  Recipe recipe, {
  DateTime? day,
}) async {
  if (recipe.nutrition.isEmpty) {
    _toast(context,
        'This recipe has no nutrition yet. Edit it and use "Calculate from ingredients".');
    return;
  }
  String meal = _guessMeal();
  double servings = 1;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => AlertDialog(
        title: const Text('Add to food diary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(recipe.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: meal,
              decoration: const InputDecoration(labelText: 'Meal'),
              items: <DropdownMenuItem<String>>[
                for (final String m in kMeals)
                  DropdownMenuItem<String>(value: m, child: Text(mealLabel(m))),
              ],
              onChanged: (String? v) => set(() => meal = v ?? meal),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text('Servings eaten'),
                const Spacer(),
                IconButton(
                  tooltip: 'Fewer servings',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed:
                      servings > 0.5 ? () => set(() => servings -= 0.5) : null,
                ),
                Text(fmtNum(servings),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'More servings',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => set(() => servings += 0.5),
                ),
              ],
            ),
            Text(
              '${fmtNum((recipe.nutrition.calories ?? 0) * servings, decimals: 0)} calories',
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(nutritionRepositoryProvider).add(
          day: day ?? _today(),
          meal: meal,
          title: recipe.title,
          servings: servings,
          perServing: recipe.nutrition,
          recipeId: recipe.id,
        );
    ref.invalidate(foodLogProvider);
    if (context.mounted) _toast(context, 'Added to your food diary.');
  } catch (e) {
    if (context.mounted) _toast(context, Failure.from(e).message);
  }
}

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nutrition'),
          bottom: const TabBar(tabs: <Tab>[
            Tab(text: 'Today'),
            Tab(text: 'Trends'),
            Tab(text: 'Goals'),
          ]),
        ),
        body: const TabBarView(children: <Widget>[
          _TodayTab(),
          _TrendsTab(),
          _GoalsTab(),
        ]),
      ),
    );
  }
}

Map<String, double> _totals(Iterable<FoodLogEntry> entries) =>
    Nutrition.sum(entries.map((FoodLogEntry e) => e.nutrition));

class _Pad extends StatelessWidget {
  const _Pad({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: children,
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

// ---------------------------------------------------------------- Today

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime day = ref.watch(selectedDayProvider);
    final AsyncValue<List<FoodLogEntry>> log = ref.watch(foodLogProvider);
    final AsyncValue<NutritionGoals> goalsAsync =
        ref.watch(nutritionGoalsProvider);
    final NutritionGoals goals = goalsAsync.value ?? const NutritionGoals();
    final DateTime today = _today();
    final bool isToday = day == today;
    final bool canBack = day.isAfter(today.subtract(const Duration(days: 89)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLogSheet(context, ref, day),
        icon: const Icon(Icons.add),
        label: const Text('Log food'),
      ),
      body: log.when(
        loading: () => const _Loading(),
        error: (Object e, StackTrace _) =>
            Center(child: Text(Failure.from(e).message)),
        data: (List<FoodLogEntry> all) {
          final List<FoodLogEntry> entries = all
              .where((FoodLogEntry e) => e.day == day)
              .toList(growable: false);
          final Map<String, double> t = _totals(entries);
          final double eaten = t['calories'] ?? 0;
          return _Pad(children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: canBack
                      ? () => ref.read(selectedDayProvider.notifier).state =
                          day.subtract(const Duration(days: 1))
                      : null,
                ),
                SizedBox(
                  width: 170,
                  child: Text(
                    isToday
                        ? 'Today'
                        : day == today.subtract(const Duration(days: 1))
                            ? 'Yesterday'
                            : '${day.month}/${day.day}/${day.year}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isToday
                      ? null
                      : () => ref.read(selectedDayProvider.notifier).state =
                          day.add(const Duration(days: 1)),
                ),
              ],
            ),
            _Card(
              title: 'Calories',
              child: Column(
                children: <Widget>[
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 24,
                    runSpacing: 12,
                    children: <Widget>[
                      CalorieRing(eaten: eaten, goal: goals.calories),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Goal  ${goals.calories}'),
                          Text('Food  ${fmtNum(eaten, decimals: 0)}'),
                          Text(
                            'Left  ${fmtNum(goals.calories - eaten, decimals: 0)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  MacroSplitBar(
                    carbs: (t['carbs_g'] ?? 0) * 4,
                    fat: (t['fat_g'] ?? 0) * 9,
                    protein: (t['protein_g'] ?? 0) * 4,
                  ),
                ],
              ),
            ),
            _Card(
                title: 'Macros and limits',
                child: GoalBars(values: t, goals: goals)),
            for (final String meal in kMeals)
              _MealSection(
                meal: meal,
                day: day,
                entries:
                    entries.where((FoodLogEntry e) => e.meal == meal).toList(),
              ),
            _Card(
              title: 'Vitamins and minerals (% of daily value)',
              child: entries.isEmpty
                  ? const Text(
                      'Log some food to see your vitamins and minerals.')
                  : DailyValueBars(values: t),
            ),
          ]);
        },
      ),
    );
  }
}

class _MealSection extends ConsumerWidget {
  const _MealSection({
    required this.meal,
    required this.day,
    required this.entries,
  });

  final String meal;
  final DateTime day;
  final List<FoodLogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double kcal = entries.fold(
        0, (double a, FoodLogEntry e) => a + (e.nutrition['calories'] ?? 0));
    return _Card(
      title: '${mealLabel(meal)}  ·  ${fmtNum(kcal, decimals: 0)} cal',
      child: Column(
        children: <Widget>[
          if (entries.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showLogSheet(context, ref, day, meal: meal),
                icon: const Icon(Icons.add),
                label: Text('Add ${meal == 'snack' ? 'a snack' : meal}'),
              ),
            ),
          for (final FoodLogEntry e in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.title),
              subtitle: Text(
                '${fmtNum(e.servings)} serving${e.servings == 1 ? '' : 's'}  ·  '
                '${fmtNum(e.nutrition['calories'] ?? 0, decimals: 0)} cal  ·  '
                'P ${fmtNum(e.nutrition['protein_g'] ?? 0, decimals: 0)}  '
                'C ${fmtNum(e.nutrition['carbs_g'] ?? 0, decimals: 0)}  '
                'F ${fmtNum(e.nutrition['fat_g'] ?? 0, decimals: 0)}',
              ),
              trailing: IconButton(
                tooltip: 'Remove ${e.title}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  try {
                    await ref.read(nutritionRepositoryProvider).delete(e.id);
                    ref.invalidate(foodLogProvider);
                  } catch (err) {
                    if (context.mounted) {
                      _toast(context, Failure.from(err).message);
                    }
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _showLogSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day, {
  String? meal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => _LogSheet(day: day, meal: meal),
  );
}

class _LogSheet extends ConsumerStatefulWidget {
  const _LogSheet({required this.day, this.meal});

  final DateTime day;
  final String? meal;

  @override
  ConsumerState<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<_LogSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Recipe>> recipes = ref.watch(recipeListProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Log food', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search your recipes',
                ),
                onChanged: (String v) => setState(() => _q = v.toLowerCase()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _quickAdd(context, ref, widget.day, widget.meal);
                },
                icon: const Icon(Icons.flash_on_outlined),
                label: const Text('Quick add calories and macros'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: recipes.when(
                  loading: () => const _Loading(),
                  error: (Object e, StackTrace _) =>
                      Center(child: Text(Failure.from(e).message)),
                  data: (List<Recipe> list) {
                    final List<Recipe> shown = list
                        .where((Recipe r) => r.title.toLowerCase().contains(_q))
                        .toList();
                    if (shown.isEmpty) {
                      return const Center(child: Text('No recipes found.'));
                    }
                    return ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (BuildContext _, int i) {
                        final Recipe r = shown[i];
                        final int? kcal = r.nutrition.calories;
                        return ListTile(
                          title: Text(r.title),
                          subtitle: Text(kcal == null
                              ? 'No nutrition yet'
                              : '$kcal cal per serving'),
                          enabled: !r.nutrition.isEmpty,
                          onTap: () async {
                            Navigator.pop(context);
                            await logRecipeToDiary(context, ref, r,
                                day: widget.day);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _quickAdd(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
  String? initialMeal,
) async {
  final TextEditingController name = TextEditingController();
  final Map<String, TextEditingController> f = <String, TextEditingController>{
    for (final String k in <String>[
      'calories',
      'protein_g',
      'carbs_g',
      'fat_g'
    ])
      k: TextEditingController(),
  };
  String meal = initialMeal ?? _guessMeal();
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => AlertDialog(
        title: const Text('Quick add'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: name,
                maxLength: 160,
                decoration:
                    const InputDecoration(labelText: 'What did you eat?'),
              ),
              DropdownButtonFormField<String>(
                initialValue: meal,
                decoration: const InputDecoration(labelText: 'Meal'),
                items: <DropdownMenuItem<String>>[
                  for (final String m in kMeals)
                    DropdownMenuItem<String>(
                        value: m, child: Text(mealLabel(m))),
                ],
                onChanged: (String? v) => set(() => meal = v ?? meal),
              ),
              for (final MapEntry<String, String> e in <String, String>{
                'calories': 'Calories',
                'protein_g': 'Protein (g)',
                'carbs_g': 'Carbs (g)',
                'fat_g': 'Fat (g)',
              }.entries)
                TextField(
                  controller: f[e.key],
                  decoration: InputDecoration(labelText: e.value),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  Nutrition n = const Nutrition();
  f.forEach((String k, TextEditingController c) {
    final double? v = double.tryParse(c.text);
    if (v != null) {
      n = n.withValue(k, v.clamp(0, k == 'calories' ? 5000 : 500).toDouble());
    }
  });
  try {
    await ref.read(nutritionRepositoryProvider).add(
          day: day,
          meal: meal,
          title: name.text,
          servings: 1,
          perServing: n,
        );
    ref.invalidate(foodLogProvider);
  } catch (e) {
    if (context.mounted) _toast(context, Failure.from(e).message);
  }
}

// --------------------------------------------------------------- Trends

class _TrendsTab extends ConsumerStatefulWidget {
  const _TrendsTab();

  @override
  ConsumerState<_TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends ConsumerState<_TrendsTab> {
  int _days = 7;
  String _nutrient = 'fiber_g';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<FoodLogEntry>> log = ref.watch(foodLogProvider);
    final NutritionGoals goals =
        ref.watch(nutritionGoalsProvider).value ?? const NutritionGoals();
    return log.when(
      loading: () => const _Loading(),
      error: (Object e, StackTrace _) =>
          Center(child: Text(Failure.from(e).message)),
      data: (List<FoodLogEntry> all) {
        final DateTime today = _today();
        final List<DateTime> days = <DateTime>[
          for (int i = _days - 1; i >= 0; i--)
            today.subtract(Duration(days: i)),
        ];
        final List<Map<String, double>> perDay = <Map<String, double>>[
          for (final DateTime d in days)
            _totals(all.where((FoodLogEntry e) => e.day == d)),
        ];
        final List<String> labels = <String>[
          for (final DateTime d in days) '${d.month}/${d.day}',
        ];
        final List<int> logged = <int>[
          for (int i = 0; i < perDay.length; i++)
            if (perDay[i].isNotEmpty) i,
        ];
        double avg(String k) => logged.isEmpty
            ? 0
            : logged.fold(0.0, (double a, int i) => a + (perDay[i][k] ?? 0)) /
                logged.length;

        final NutrientDef def =
            kAllNutrients.firstWhere((NutrientDef d) => d.key == _nutrient);
        final double? target = goals.targetFor(def);

        return _Pad(children: <Widget>[
          Center(
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 7, label: Text('7 days')),
                ButtonSegment<int>(value: 30, label: Text('30 days')),
                ButtonSegment<int>(value: 90, label: Text('90 days')),
              ],
              selected: <int>{_days},
              onSelectionChanged: (Set<int> s) =>
                  setState(() => _days = s.first),
            ),
          ),
          const SizedBox(height: 12),
          if (logged.isEmpty)
            const _Card(
              title: 'No data yet',
              child: Text(
                  'Log food on the Today tab and your trends will appear here.'),
            )
          else ...<Widget>[
            _Card(
              title: 'Calories per day',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Average ${fmtNum(avg('calories'), decimals: 0)} of ${goals.calories} goal '
                    '(${logged.length} logged day${logged.length == 1 ? '' : 's'})',
                  ),
                  const SizedBox(height: 8),
                  StackedBarChart(
                    stacks: <List<double>>[
                      for (final Map<String, double> m in perDay)
                        <double>[m['calories'] ?? 0],
                    ],
                    labels: labels,
                    colors: <Color>[Theme.of(context).colorScheme.primary],
                    goal: goals.calories.toDouble(),
                    semanticSummary:
                        'Calories per day for the last $_days days with the goal line',
                  ),
                  Text('Line = daily goal',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            _Card(
              title: 'Where your calories come from',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MacroSplitBar(
                    carbs: avg('carbs_g') * 4,
                    fat: avg('fat_g') * 9,
                    protein: avg('protein_g') * 4,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Goal split: carbs ${goals.carbsPct}% · fat ${goals.fatPct}% · protein ${goals.proteinPct}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  StackedBarChart(
                    stacks: <List<double>>[
                      for (final Map<String, double> m in perDay)
                        <double>[
                          (m['carbs_g'] ?? 0) * 4,
                          (m['fat_g'] ?? 0) * 9,
                          (m['protein_g'] ?? 0) * 4,
                        ],
                    ],
                    labels: labels,
                    colors: const <Color>[kCarbColor, kFatColor, kProteinColor],
                    semanticSummary:
                        'Calories from carbs, fat and protein per day',
                  ),
                ],
              ),
            ),
            _Card(
              title: 'Average vs goals',
              child: GoalBars(
                values: <String, double>{
                  for (final NutrientDef d in kAllNutrients) d.key: avg(d.key),
                },
                goals: goals,
              ),
            ),
            _Card(
              title: 'Any nutrient',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _nutrient,
                    decoration: const InputDecoration(labelText: 'Nutrient'),
                    items: <DropdownMenuItem<String>>[
                      for (final NutrientDef d in kAllNutrients)
                        DropdownMenuItem<String>(
                          value: d.key,
                          child: Text(d.unit.isEmpty
                              ? d.label
                              : '${d.label} (${d.unit})'),
                        ),
                    ],
                    onChanged: (String? v) =>
                        setState(() => _nutrient = v ?? _nutrient),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Average ${fmtNum(avg(_nutrient))} ${def.unit}'
                    '${target == null ? '' : ' of ${fmtNum(target)} ${def.unit} (${(avg(_nutrient) / target * 100).round()}%)'}',
                  ),
                  const SizedBox(height: 8),
                  StackedBarChart(
                    stacks: <List<double>>[
                      for (final Map<String, double> m in perDay)
                        <double>[m[_nutrient] ?? 0],
                    ],
                    labels: labels,
                    colors: <Color>[Theme.of(context).colorScheme.tertiary],
                    goal: target,
                    semanticSummary: '${def.label} per day',
                  ),
                ],
              ),
            ),
            _Card(
              title: 'Vitamins and minerals, average % of daily value',
              child: DailyValueBars(
                values: <String, double>{
                  for (final NutrientDef d in kAllNutrients) d.key: avg(d.key),
                },
              ),
            ),
          ],
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- Goals

class _GoalsTab extends ConsumerStatefulWidget {
  const _GoalsTab();

  @override
  ConsumerState<_GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends ConsumerState<_GoalsTab> {
  final TextEditingController _cal = TextEditingController();
  final TextEditingController _carb = TextEditingController();
  final TextEditingController _pro = TextEditingController();
  final TextEditingController _fat = TextEditingController();
  final TextEditingController _fiber = TextEditingController();
  final TextEditingController _sugar = TextEditingController();
  final TextEditingController _sodium = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  static const Map<String, List<int>> _presets = <String, List<int>>{
    'Balanced (50 / 20 / 30)': <int>[50, 20, 30],
    'High protein (35 / 35 / 30)': <int>[35, 35, 30],
    'Lower carb (25 / 30 / 45)': <int>[25, 30, 45],
    'Keto (5 / 25 / 70)': <int>[5, 25, 70],
  };

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _cal,
      _carb,
      _pro,
      _fat,
      _fiber,
      _sugar,
      _sodium,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(NutritionGoals g) {
    _cal.text = '${g.calories}';
    _carb.text = '${g.carbsPct}';
    _pro.text = '${g.proteinPct}';
    _fat.text = '${g.fatPct}';
    _fiber.text = fmtNum(g.fiberG);
    _sugar.text = fmtNum(g.sugarG);
    _sodium.text = '${g.sodiumMg}';
  }

  int _i(TextEditingController c) => int.tryParse(c.text) ?? 0;

  Future<void> _save() async {
    final int cal = _i(_cal);
    final int sum = _i(_carb) + _i(_pro) + _i(_fat);
    if (cal < 500 || cal > 10000) {
      _toast(context, 'Calories must be between 500 and 10,000.');
      return;
    }
    if (sum != 100) {
      _toast(
          context, 'Carbs, protein and fat must add up to 100% (now $sum%).');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(nutritionRepositoryProvider).saveGoals(
            NutritionGoals.fromSplit(
              calories: cal,
              carbsPct: _i(_carb),
              proteinPct: _i(_pro),
              fatPct: _i(_fat),
              fiberG: double.tryParse(_fiber.text) ?? 28,
              sugarG: double.tryParse(_sugar.text) ?? 50,
              sodiumMg: _i(_sodium) == 0 ? 2300 : _i(_sodium),
            ),
          );
      ref.invalidate(nutritionGoalsProvider);
      if (mounted) _toast(context, 'Goals saved.');
    } catch (e) {
      if (mounted) _toast(context, Failure.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _num(TextEditingController c, String label, {String? suffix}) =>
      SizedBox(
        width: 150,
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final AsyncValue<NutritionGoals> goals = ref.watch(nutritionGoalsProvider);
    return goals.when(
      loading: () => const _Loading(),
      error: (Object e, StackTrace _) =>
          Center(child: Text(Failure.from(e).message)),
      data: (NutritionGoals g) {
        if (!_loaded) {
          _loaded = true;
          _fill(g);
        }
        final int cal = _i(_cal);
        final int sum = _i(_carb) + _i(_pro) + _i(_fat);
        return _Pad(children: <Widget>[
          _Card(
            title: 'Daily calories and macros',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _num(_cal, 'Calorie goal', suffix: 'cal'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: null,
                  decoration: const InputDecoration(
                      labelText: 'Macro preset (carbs / protein / fat)'),
                  items: <DropdownMenuItem<String>>[
                    for (final String k in _presets.keys)
                      DropdownMenuItem<String>(value: k, child: Text(k)),
                  ],
                  onChanged: (String? k) {
                    if (k == null) return;
                    final List<int> p = _presets[k]!;
                    setState(() {
                      _carb.text = '${p[0]}';
                      _pro.text = '${p[1]}';
                      _fat.text = '${p[2]}';
                    });
                  },
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  _num(_carb, 'Carbs', suffix: '%'),
                  _num(_pro, 'Protein', suffix: '%'),
                  _num(_fat, 'Fat', suffix: '%'),
                ]),
                const SizedBox(height: 8),
                Text(
                  sum == 100
                      ? '= ${fmtNum(cal * _i(_carb) / 400, decimals: 0)} g carbs · '
                          '${fmtNum(cal * _i(_pro) / 400, decimals: 0)} g protein · '
                          '${fmtNum(cal * _i(_fat) / 900, decimals: 0)} g fat'
                      : 'Percentages add up to $sum%. They need to total 100%.',
                  style: TextStyle(
                    color:
                        sum == 100 ? null : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          _Card(
            title: 'Daily limits',
            child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              _num(_fiber, 'Fiber (min)', suffix: 'g'),
              _num(_sugar, 'Sugar (max)', suffix: 'g'),
              _num(_sodium, 'Sodium (max)', suffix: 'mg'),
            ]),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_saving ? 'Saving…' : 'Save goals'),
          ),
          const SizedBox(height: 12),
          _CalorieCalculator(
              onUse: (int kcal) => setState(() => _cal.text = '$kcal')),
          const _Card(
            title: 'About vitamin and mineral targets',
            child: Text(
              'Vitamins and minerals are measured against the FDA Daily Values '
              'for adults (a 2,000 calorie reference diet). 100% means you met '
              'the daily value. Individual needs vary, so talk to a doctor or '
              'dietitian for medical advice.',
            ),
          ),
        ]);
      },
    );
  }
}

class _CalorieCalculator extends StatefulWidget {
  const _CalorieCalculator({required this.onUse});

  final ValueChanged<int> onUse;

  @override
  State<_CalorieCalculator> createState() => _CalorieCalculatorState();
}

class _CalorieCalculatorState extends State<_CalorieCalculator> {
  bool _male = true;
  final TextEditingController _age = TextEditingController(text: '30');
  final TextEditingController _ft = TextEditingController(text: '5');
  final TextEditingController _inch = TextEditingController(text: '9');
  final TextEditingController _lb = TextEditingController(text: '170');
  double _activity = 1.375;
  int _goalDelta = 0;

  @override
  void dispose() {
    _age.dispose();
    _ft.dispose();
    _inch.dispose();
    _lb.dispose();
    super.dispose();
  }

  /// Mifflin-St Jeor estimate of daily energy needs.
  int get _kcal {
    final double kg = (double.tryParse(_lb.text) ?? 0) * 0.45359;
    final double cm = ((double.tryParse(_ft.text) ?? 0) * 12 +
            (double.tryParse(_inch.text) ?? 0)) *
        2.54;
    final double age = double.tryParse(_age.text) ?? 0;
    final double bmr = 10 * kg + 6.25 * cm - 5 * age + (_male ? 5 : -161);
    return (bmr * _activity + _goalDelta).round().clamp(1200, 6000);
  }

  Widget _f(TextEditingController c, String l, double w) => SizedBox(
        width: w,
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: l, isDense: true),
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: const Text('Calorie calculator'),
        subtitle: const Text('Estimate a goal from your body and activity'),
        childrenPadding: const EdgeInsets.all(14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('Male')),
              ButtonSegment<bool>(value: false, label: Text('Female')),
            ],
            selected: <bool>{_male},
            onSelectionChanged: (Set<bool> s) =>
                setState(() => _male = s.first),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            _f(_age, 'Age', 80),
            _f(_ft, 'Height ft', 90),
            _f(_inch, 'in', 70),
            _f(_lb, 'Weight lb', 100),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<double>(
            initialValue: _activity,
            decoration: const InputDecoration(labelText: 'Activity level'),
            items: const <DropdownMenuItem<double>>[
              DropdownMenuItem<double>(value: 1.2, child: Text('Sedentary')),
              DropdownMenuItem<double>(
                  value: 1.375, child: Text('Lightly active')),
              DropdownMenuItem<double>(
                  value: 1.55, child: Text('Moderately active')),
              DropdownMenuItem<double>(
                  value: 1.725, child: Text('Very active')),
            ],
            onChanged: (double? v) =>
                setState(() => _activity = v ?? _activity),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _goalDelta,
            decoration: const InputDecoration(labelText: 'Goal'),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(
                  value: -500, child: Text('Lose about 1 lb a week')),
              DropdownMenuItem<int>(
                  value: -250, child: Text('Lose about ½ lb a week')),
              DropdownMenuItem<int>(value: 0, child: Text('Maintain weight')),
              DropdownMenuItem<int>(
                  value: 250, child: Text('Gain about ½ lb a week')),
            ],
            onChanged: (int? v) => setState(() => _goalDelta = v ?? _goalDelta),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: Text('About $_kcal calories a day',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.tonal(
              onPressed: () => widget.onUse(_kcal),
              child: const Text('Use this'),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'A general estimate, not medical advice.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
