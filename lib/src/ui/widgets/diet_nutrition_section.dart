import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/nutrition_estimator.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../state/recipe_controllers.dart';
import 'diet_chips.dart';

String _fmt(double v) {
  final double r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? '${r.toInt()}' : '$r';
}

/// Collapsed by default: diet labels plus the full per-serving label.
class DietNutritionSection extends ConsumerStatefulWidget {
  const DietNutritionSection({super.key});

  @override
  ConsumerState<DietNutritionSection> createState() =>
      _DietNutritionSectionState();
}

class _DietNutritionSectionState extends ConsumerState<DietNutritionSection> {
  /// Bumped when the calculator fills values in, so the text fields
  /// rebuild with the new numbers.
  int _version = 0;

  void _calculate() {
    final RecipeDraft draft = ref.read(recipeFormProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (draft.ingredients.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Add ingredients with amounts first.'),
      ));
      return;
    }
    final NutritionEstimate est =
        NutritionEstimator.estimate(draft.ingredients, draft.baseServings);
    if (est.counted.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'No ingredients could be matched. Use common whole foods with an amount, like "2 cups flour".'),
      ));
      return;
    }
    ref.read(recipeFormProvider.notifier).setNutrition(
          est.nutrition.withServingSize(draft.nutrition.servingSize),
        );
    setState(() => _version++);
    final String skipped =
        est.skipped.isEmpty ? '' : ' Not counted: ${est.skipped.join(', ')}.';
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(
          'Calculated from ${est.counted.length} ingredient${est.counted.length == 1 ? '' : 's'}, per serving (recipe makes ${draft.baseServings}).$skipped'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final RecipeDraft draft = ref.watch(recipeFormProvider);
    final RecipeFormController c = ref.read(recipeFormProvider.notifier);
    final bool hasAny = draft.diets.isNotEmpty || !draft.nutrition.isEmpty;

    Widget numberField(NutrientDef d) {
      final String unit = d.unit.isEmpty ? '' : ' (${d.unit})';
      return SizedBox(
        width: 150,
        child: TextFormField(
          key: ValueKey<String>('${d.key}-$_version'),
          initialValue: draft.nutrition[d.key] == null
              ? ''
              : _fmt(draft.nutrition[d.key]!),
          decoration:
              InputDecoration(labelText: '${d.label}$unit', isDense: true),
          keyboardType: TextInputType.numberWithOptions(decimal: !d.whole),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
              d.whole ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
            ),
          ],
          onChanged: (String v) => c.setNutrition(
            ref.read(recipeFormProvider).nutrition.withValue(
                  d.key,
                  v.isEmpty ? null : double.tryParse(v),
                ),
          ),
        ),
      );
    }

    Widget group(String title, List<NutrientDef> defs) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final NutrientDef d in defs) numberField(d)
              ],
            ),
          ],
        );

    NutrientDef def(String k) =>
        kAllNutrients.firstWhere((NutrientDef d) => d.key == k);
    List<NutrientDef> defs(List<String> keys) => keys.map(def).toList();

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
          FilledButton.tonalIcon(
            onPressed: _calculate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Calculate from ingredients'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Fills in every nutrient from your ingredient names and amounts '
              '(whole foods only, estimates per serving). You can edit any value.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 310,
            child: TextFormField(
              key: ValueKey<String>('serving-$_version'),
              initialValue: draft.nutrition.servingSize ?? '',
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Serving size',
                hintText: 'e.g. 1 cup (240 g)',
                isDense: true,
              ),
              onChanged: (String v) => c.setNutrition(
                ref.read(recipeFormProvider).nutrition.withServingSize(v),
              ),
            ),
          ),
          group('Energy', <NutrientDef>[kCalories]),
          group(
              'Macros',
              defs(<String>[
                'protein_g',
                'carbs_g',
                'fat_g',
                'fiber_g',
                'sugar_g',
                'added_sugar_g',
              ])),
          group(
              'Fat breakdown',
              defs(<String>[
                'sat_fat_g',
                'trans_fat_g',
                'poly_fat_g',
                'mono_fat_g',
              ])),
          group(
              'Cholesterol & salt',
              defs(<String>[
                'cholesterol_mg',
                'sodium_mg',
              ])),
          group(
              'Vitamins & minerals',
              defs(<String>[
                'potassium_mg',
                'calcium_mg',
                'iron_mg',
                'vitamin_d_mcg',
                'vitamin_a_mcg',
                'vitamin_c_mg',
                ...kMicroExtras.map((NutrientDef d) => d.key),
              ])),
        ],
      ),
    );
  }
}

const Color _carbColor = Color(0xFF1E88E5);
const Color _fatColor = Color(0xFFF9A825);
const Color _proteinColor = Color(0xFF43A047);

/// FDA-style Nutrition Facts label with a macro split and an adjustable
/// number of servings, like a food-diary entry.
class NutritionFactsPanel extends StatefulWidget {
  const NutritionFactsPanel({
    super.key,
    required this.nutrition,
    required this.servings,
  });

  final Nutrition nutrition;
  final int servings;

  @override
  State<NutritionFactsPanel> createState() => _NutritionFactsPanelState();
}

class _NutritionFactsPanelState extends State<NutritionFactsPanel> {
  double _eaten = 1;

  void _step(double delta) =>
      setState(() => _eaten = (_eaten + delta).clamp(0.5, 20).toDouble());

  Nutrition _scaled() {
    final Nutrition n = widget.nutrition;
    if (_eaten == 1) return n;
    return Nutrition(
      values: <String, double>{
        for (final MapEntry<String, double> e in n.values.entries)
          e.key: e.value * _eaten,
      },
      servingSize: n.servingSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Nutrition n = _scaled();
    final Color line = theme.colorScheme.onSurface;
    final TextStyle? small = theme.textTheme.bodySmall;
    final double? kcal = n['calories'];
    final split = n.macroSplit;

    Widget thick() => Divider(thickness: 8, height: 12, color: line);
    Widget thin() => Divider(thickness: 1, height: 1, color: line);

    Widget row(NutrientDef d) {
      final double? v = n[d.key];
      if (v == null) return const SizedBox.shrink();
      final int? pct = n.percentDv(d);
      return Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(left: 14.0 * d.indent, top: 3, bottom: 3),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: d.label,
                          style: TextStyle(
                            fontWeight:
                                d.bold ? FontWeight.w800 : FontWeight.w400,
                          ),
                        ),
                        TextSpan(text: ' ${_fmt(v)}${d.unit}'),
                      ],
                    ),
                  ),
                ),
                if (pct != null)
                  Text('$pct%',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          thin(),
        ],
      );
    }

    final List<Widget> rows = <Widget>[];
    bool vitaminsDivider = false;
    for (final NutrientDef d in kLabelNutrients) {
      if (!vitaminsDivider && d.key == 'vitamin_d_mcg') {
        vitaminsDivider = true;
        if (kLabelNutrients
            .skipWhile((NutrientDef x) => x.key != 'vitamin_d_mcg')
            .any((NutrientDef x) => n[x.key] != null)) {
          rows.add(thick());
        }
      }
      rows.add(row(d));
    }
    for (final NutrientDef d in kMicroExtras) {
      rows.add(row(d));
    }

    return Semantics(
      container: true,
      label: 'Nutrition facts',
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: line, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Nutrition Facts',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text('${widget.servings} servings per recipe', style: small),
            if (widget.nutrition.servingSize != null)
              Text('Serving size: ${widget.nutrition.servingSize}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Text('Servings eaten', style: small),
                const Spacer(),
                IconButton(
                  tooltip: 'Fewer servings',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _eaten > 0.5 ? () => _step(-0.5) : null,
                ),
                Text(_fmt(_eaten),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'More servings',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _eaten < 20 ? () => _step(0.5) : null,
                ),
              ],
            ),
            thick(),
            if (kcal != null) ...<Widget>[
              Text('Amount per serving', style: small),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('Calories',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Text(
                    '${kcal.round()}',
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ],
            if (split != null) ...<Widget>[
              const SizedBox(height: 6),
              _MacroBar(split: split),
            ],
            thick(),
            Align(
              alignment: Alignment.centerRight,
              child: Text('% Daily Value*',
                  style: small?.copyWith(fontWeight: FontWeight.w800)),
            ),
            thin(),
            ...rows,
            const SizedBox(height: 6),
            Text(
              '* The % Daily Value tells you how much a nutrient in a serving '
              'contributes to a daily diet. 2,000 calories a day is used for '
              'general nutrition advice.',
              style: small,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.split});

  final ({double carbs, double fat, double protein}) split;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    int pct(double v) => (v * 100).round();
    int flex(double v) => (v * 1000).round().clamp(1, 1000);

    Widget legend(Color c, String label, double v) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('$label ${pct(v)}%', style: t.bodySmall),
          ],
        );

    return Semantics(
      label: 'Calories from carbs ${pct(split.carbs)} percent, '
          'fat ${pct(split.fat)} percent, protein ${pct(split.protein)} percent',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: <Widget>[
                  Expanded(
                      flex: flex(split.carbs),
                      child: const ColoredBox(color: _carbColor)),
                  Expanded(
                      flex: flex(split.fat),
                      child: const ColoredBox(color: _fatColor)),
                  Expanded(
                      flex: flex(split.protein),
                      child: const ColoredBox(color: _proteinColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            children: <Widget>[
              legend(_carbColor, 'Carbs', split.carbs),
              legend(_fatColor, 'Fat', split.fat),
              legend(_proteinColor, 'Protein', split.protein),
            ],
          ),
        ],
      ),
    );
  }
}
