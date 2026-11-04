import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../../data/repositories/nutrition_repository.dart';

const Color kCarbColor = Color(0xFF1E88E5);
const Color kFatColor = Color(0xFFF9A825);
const Color kProteinColor = Color(0xFF43A047);

String fmtNum(double v, {int decimals = 1}) {
  final double f = decimals == 0 ? 1 : (decimals == 1 ? 10 : 100);
  final double r = (v * f).round() / f;
  return r == r.roundToDouble() ? '${r.toInt()}' : '$r';
}

/// A labelled progress bar. Bars cap at 100% visually, the number does not.
class ProgressRow extends StatelessWidget {
  const ProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    this.color,
    this.isLimit = false,
  });

  final String label;
  final double value;
  final double target;
  final String unit;
  final Color? color;

  /// Limits (sugar, sodium) turn red when exceeded; goals turn green.
  final bool isLimit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double ratio = target <= 0 ? 0 : value / target;
    final int pct = (ratio * 100).round();
    final bool over = ratio > 1;
    final Color bar = over && isLimit
        ? theme.colorScheme.error
        : (color ?? theme.colorScheme.primary);
    return Semantics(
      label: '$label ${fmtNum(value)} of ${fmtNum(target)} $unit, $pct percent',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                Text(
                  '${fmtNum(value)} / ${fmtNum(target)} $unit  ·  $pct%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1).toDouble(),
                minHeight: 8,
                color: bar,
                backgroundColor: bar.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every vitamin and mineral as "% of Daily Value" out of 100. With
/// [showMissing] false, nutrients that have no data are left out (used for
/// a single recipe where many values are simply unknown).
class DailyValueBars extends StatelessWidget {
  const DailyValueBars({
    super.key,
    required this.values,
    this.showMissing = true,
  });

  final Map<String, double> values;
  final bool showMissing;

  @override
  Widget build(BuildContext context) {
    final List<NutrientDef> defs = kVitaminMineralDefs
        .where((NutrientDef d) => showMissing || values[d.key] != null)
        .toList();
    if (defs.isEmpty) return const SizedBox.shrink();

    List<Widget> section(String title, bool Function(NutrientDef) test) {
      final List<NutrientDef> items = defs.where(test).toList();
      if (items.isEmpty) return const <Widget>[];
      return <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final NutrientDef d in items)
          ProgressRow(
            label: d.label,
            value: values[d.key] ?? 0,
            target: d.dailyValue ?? 1,
            unit: d.unit,
          ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...section('Vitamins', (NutrientDef d) => kVitaminKeys.contains(d.key)),
        ...section(
            'Minerals', (NutrientDef d) => !kVitaminKeys.contains(d.key)),
      ],
    );
  }
}

/// Ring showing calories eaten against the goal.
class CalorieRing extends StatelessWidget {
  const CalorieRing({super.key, required this.eaten, required this.goal});

  final double eaten;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double remaining = goal - eaten;
    final bool over = remaining < 0;
    final Color color =
        over ? theme.colorScheme.error : theme.colorScheme.primary;
    return Semantics(
      label: over
          ? '${fmtNum(-remaining, decimals: 0)} calories over the daily goal'
          : '${fmtNum(remaining, decimals: 0)} calories remaining of $goal',
      excludeSemantics: true,
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: goal <= 0 ? 0 : (eaten / goal).clamp(0, 1).toDouble(),
                strokeWidth: 12,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  fmtNum(remaining.abs(), decimals: 0),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(over ? 'over goal' : 'remaining',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical bar chart. Each bar is a stack of segments so the same widget
/// draws single-series calorie bars and stacked macro bars.
class StackedBarChart extends StatelessWidget {
  const StackedBarChart({
    super.key,
    required this.stacks,
    required this.labels,
    required this.colors,
    this.goal,
    this.height = 150,
    this.semanticSummary = 'Bar chart',
  });

  final List<List<double>> stacks;
  final List<String> labels;
  final List<Color> colors;
  final double? goal;
  final double height;
  final String semanticSummary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    double maxV = goal ?? 0;
    for (final List<double> s in stacks) {
      final double t = s.fold(0, (double a, double b) => a + b);
      if (t > maxV) maxV = t;
    }
    if (maxV <= 0) maxV = 1;
    maxV *= 1.1;
    final int step = (stacks.length / 7).ceil().clamp(1, 100);

    return Semantics(
      label: semanticSummary,
      child: SizedBox(
        height: height + 22,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) => Stack(
            children: <Widget>[
              Positioned.fill(
                bottom: 22,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final List<double> s in stacks)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              for (int i = s.length - 1; i >= 0; i--)
                                if (s[i] > 0)
                                  SizedBox(
                                    height: height * s[i] / maxV,
                                    child: ColoredBox(
                                      color: colors[i % colors.length],
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (goal != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22 + height * goal! / maxV,
                  child: Container(
                    height: 2,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < labels.length; i++)
                      Expanded(
                        child: Text(
                          i % step == 0 ? labels[i] : '',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.clip,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carbs / fat / protein share of calories as one segmented bar.
class MacroSplitBar extends StatelessWidget {
  const MacroSplitBar(
      {super.key,
      required this.carbs,
      required this.fat,
      required this.protein});

  /// Calories from each macro.
  final double carbs, fat, protein;

  @override
  Widget build(BuildContext context) {
    final double total = carbs + fat + protein;
    if (total <= 0) return const SizedBox.shrink();
    int pct(double v) => (v / total * 100).round();
    int flex(double v) => (v / total * 1000).round().clamp(1, 1000);
    final TextStyle? small = Theme.of(context).textTheme.bodySmall;
    Widget legend(Color c, String l, double v) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('$l ${pct(v)}%', style: small),
          ],
        );
    return Semantics(
      label: 'Calories from carbs ${pct(carbs)} percent, fat ${pct(fat)} '
          'percent, protein ${pct(protein)} percent',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 12,
              child: Row(children: <Widget>[
                Expanded(
                    flex: flex(carbs),
                    child: const ColoredBox(color: kCarbColor)),
                Expanded(
                    flex: flex(fat), child: const ColoredBox(color: kFatColor)),
                Expanded(
                    flex: flex(protein),
                    child: const ColoredBox(color: kProteinColor)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 10, children: <Widget>[
            legend(kCarbColor, 'Carbs', carbs),
            legend(kFatColor, 'Fat', fat),
            legend(kProteinColor, 'Protein', protein),
          ]),
        ],
      ),
    );
  }
}

/// Calories, macros and limits against the user's goals.
class GoalBars extends StatelessWidget {
  const GoalBars({super.key, required this.values, required this.goals});

  final Map<String, double> values;
  final NutritionGoals goals;

  @override
  Widget build(BuildContext context) {
    double v(String k) => values[k] ?? 0;
    return Column(
      children: <Widget>[
        ProgressRow(
            label: 'Carbohydrates',
            value: v('carbs_g'),
            target: goals.carbsG,
            unit: 'g',
            color: kCarbColor),
        ProgressRow(
            label: 'Protein',
            value: v('protein_g'),
            target: goals.proteinG,
            unit: 'g',
            color: kProteinColor),
        ProgressRow(
            label: 'Fat',
            value: v('fat_g'),
            target: goals.fatG,
            unit: 'g',
            color: kFatColor),
        ProgressRow(
            label: 'Fiber',
            value: v('fiber_g'),
            target: goals.fiberG,
            unit: 'g'),
        ProgressRow(
            label: 'Sugar',
            value: v('sugar_g'),
            target: goals.sugarG,
            unit: 'g',
            isLimit: true),
        ProgressRow(
            label: 'Sodium',
            value: v('sodium_mg'),
            target: goals.sodiumMg.toDouble(),
            unit: 'mg',
            isLimit: true),
      ],
    );
  }
}
