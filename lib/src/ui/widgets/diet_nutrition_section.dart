import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../state/recipe_controllers.dart';
import 'diet_chips.dart';

/// Collapsed by default: diet labels plus per-serving nutrition facts.
class DietNutritionSection extends ConsumerWidget {
  const DietNutritionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecipeDraft draft = ref.watch(recipeFormProvider);
    final RecipeFormController c = ref.read(recipeFormProvider.notifier);
    final Nutrition n = draft.nutrition;
    final bool hasAny = draft.diets.isNotEmpty || !n.isEmpty;

    Widget field(
      String label,
      String? initial,
      Nutrition Function(Nutrition, String) apply, {
      bool decimal = true,
    }) {
      return SizedBox(
        width: 150,
        child: TextFormField(
          initialValue: initial ?? '',
          decoration: InputDecoration(labelText: label, isDense: true),
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
              decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
            ),
          ],
          onChanged: (String v) => c.setNutrition(apply(draft.nutrition, v)),
        ),
      );
    }

    String? fmt(double? v) =>
        v == null ? null : (v == v.roundToDouble() ? '${v.toInt()}' : '$v');

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: hasAny,
        title: const Text('Diet & nutrition facts'),
        subtitle: const Text('Optional. Nutrition is per serving.'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DietChips(selected: draft.diets, onToggle: c.toggleDiet),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              field(
                'Calories',
                n.calories?.toString(),
                (Nutrition o, String v) => _copy(o, calories: int.tryParse(v)),
                decimal: false,
              ),
              field(
                'Protein (g)',
                fmt(n.proteinG),
                (Nutrition o, String v) =>
                    _copy(o, proteinG: double.tryParse(v)),
              ),
              field(
                'Carbs (g)',
                fmt(n.carbsG),
                (Nutrition o, String v) => _copy(o, carbsG: double.tryParse(v)),
              ),
              field(
                'Fat (g)',
                fmt(n.fatG),
                (Nutrition o, String v) => _copy(o, fatG: double.tryParse(v)),
              ),
              field(
                'Fiber (g)',
                fmt(n.fiberG),
                (Nutrition o, String v) => _copy(o, fiberG: double.tryParse(v)),
              ),
              field(
                'Sugar (g)',
                fmt(n.sugarG),
                (Nutrition o, String v) => _copy(o, sugarG: double.tryParse(v)),
              ),
              field(
                'Sodium (mg)',
                n.sodiumMg?.toString(),
                (Nutrition o, String v) => _copy(o, sodiumMg: int.tryParse(v)),
                decimal: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Replaces exactly one field, including with null (cleared input).
Nutrition _copy(
  Nutrition o, {
  Object? calories = _keep,
  Object? proteinG = _keep,
  Object? carbsG = _keep,
  Object? fatG = _keep,
  Object? fiberG = _keep,
  Object? sugarG = _keep,
  Object? sodiumMg = _keep,
}) =>
    Nutrition(
      calories: identical(calories, _keep) ? o.calories : calories as int?,
      proteinG: identical(proteinG, _keep) ? o.proteinG : proteinG as double?,
      carbsG: identical(carbsG, _keep) ? o.carbsG : carbsG as double?,
      fatG: identical(fatG, _keep) ? o.fatG : fatG as double?,
      fiberG: identical(fiberG, _keep) ? o.fiberG : fiberG as double?,
      sugarG: identical(sugarG, _keep) ? o.sugarG : sugarG as double?,
      sodiumMg: identical(sodiumMg, _keep) ? o.sodiumMg : sodiumMg as int?,
    );

const Object _keep = Object();

/// Label-style panel of per-serving nutrition facts.
class NutritionFactsPanel extends StatelessWidget {
  const NutritionFactsPanel({
    super.key,
    required this.nutrition,
    required this.servings,
  });

  final Nutrition nutrition;
  final int servings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    String g(double v) => '${v == v.roundToDouble() ? v.toInt() : v} g';

    final List<(String, String)> rows = <(String, String)>[
      if (nutrition.proteinG != null) ('Protein', g(nutrition.proteinG!)),
      if (nutrition.carbsG != null) ('Carbohydrates', g(nutrition.carbsG!)),
      if (nutrition.sugarG != null) ('  of which sugars', g(nutrition.sugarG!)),
      if (nutrition.fatG != null) ('Fat', g(nutrition.fatG!)),
      if (nutrition.fiberG != null) ('Fiber', g(nutrition.fiberG!)),
      if (nutrition.sodiumMg != null) ('Sodium', '${nutrition.sodiumMg} mg'),
    ];

    return Semantics(
      container: true,
      label: 'Nutrition facts',
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.onSurface, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Nutrition Facts',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              'Per serving (recipe makes $servings)',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(thickness: 4, height: 14),
            if (nutrition.calories != null) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('Calories', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    '${nutrition.calories}',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const Divider(thickness: 2, height: 10),
            ],
            for (final (String, String) r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Text(r.$1),
                    const Spacer(),
                    Text(r.$2,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
