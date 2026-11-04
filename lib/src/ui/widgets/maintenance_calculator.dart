import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/energy_model.dart';
import 'nutrition_widgets.dart';

/// A quick maintenance-calorie estimate for the Nutrition goals tab.
class MaintenanceCalculator extends StatefulWidget {
  const MaintenanceCalculator({super.key, required this.onUse});

  /// Called with the estimate rounded for display.
  final ValueChanged<int> onUse;

  @override
  State<MaintenanceCalculator> createState() => _MaintenanceCalculatorState();
}

class _MaintenanceCalculatorState extends State<MaintenanceCalculator> {
  Sex _sex = Sex.male;
  WeightUnit _unit = WeightUnit.lb;
  HeightUnit _heightUnit = HeightUnit.feetInches;
  ActivityLevel _activity = ActivityLevel.sedentary;

  final TextEditingController _age = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _cm = TextEditingController();
  final TextEditingController _ft = TextEditingController();
  final TextEditingController _inch = TextEditingController();

  @override
  void dispose() {
    _age.dispose();
    _weight.dispose();
    _cm.dispose();
    _ft.dispose();
    _inch.dispose();
    super.dispose();
  }

  String get _weightUnit => _unit == WeightUnit.kg ? 'kg' : 'lb';

  double _number(TextEditingController controller, String name) {
    final double? value = double.tryParse(controller.text.trim());
    if (value == null) throw EnergyInputError('Enter your $name.');
    return value;
  }

  EnergyProfile _readProfile() {
    final double heightCm = _heightUnit == HeightUnit.cm
        ? heightToCm(HeightUnit.cm, _number(_cm, 'height'))
        : heightToCm(
            HeightUnit.feetInches,
            _number(_ft, 'height in feet'),
            inches: _inch.text.trim().isEmpty ? 0 : _number(_inch, 'height'),
          );
    return EnergyProfile(
      sex: _sex,
      ageYears: _number(_age, 'age'),
      weightKg: weightToKg(_number(_weight, 'weight'), _unit),
      heightCm: heightCm,
      activity: _activity,
      equation: BmrEquation.mifflinStJeor,
    );
  }

  double? _currentHeightCm() {
    try {
      if (_heightUnit == HeightUnit.cm) {
        return heightToCm(HeightUnit.cm, double.parse(_cm.text.trim()));
      }
      return heightToCm(
        HeightUnit.feetInches,
        double.parse(_ft.text.trim()),
        inches: _inch.text.trim().isEmpty ? 0 : double.parse(_inch.text.trim()),
      );
    } on FormatException {
      return null;
    } on EnergyInputError {
      return null;
    }
  }

  void _changeUnits(WeightUnit next) {
    if (next == _unit) return;
    final double? weight = double.tryParse(_weight.text.trim());
    final double? heightCm = _currentHeightCm();
    setState(() {
      if (weight != null) {
        final double kg = weightToKg(weight, _unit);
        _weight.text = fmtNum(next == WeightUnit.kg ? kg : kg / kgPerLb);
      }
      _unit = next;
      _heightUnit =
          next == WeightUnit.kg ? HeightUnit.cm : HeightUnit.feetInches;
      if (heightCm != null) {
        if (_heightUnit == HeightUnit.cm) {
          _cm.text = fmtNum(heightCm);
        } else {
          final double totalInches = heightCm / cmPerInch;
          _ft.text = '${totalInches ~/ 12}';
          _inch.text = fmtNum(totalInches - (totalInches ~/ 12) * 12);
        }
      }
    });
  }

  Widget _field(
    TextEditingController controller,
    String label,
    double width, {
    String? suffix,
    bool decimal = true,
  }) =>
      SizedBox(
        width: width,
        child: TextField(
          key: ValueKey<String>('maintenance-$label'),
          controller: controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            isDense: true,
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
              RegExp(decimal ? r'[0-9.]' : r'[0-9]'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    FormulaEstimate? estimate;
    String? estimateMessage;
    try {
      estimate = formulaTdee(_readProfile());
    } on EnergyInputError catch (error) {
      estimateMessage = error.message.startsWith('Enter your ')
          ? 'Enter your age, weight, and height to see an estimate.'
          : error.message;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: const Text('Maintenance calories'),
        subtitle: const Text('A quick starting estimate'),
        childrenPadding: const EdgeInsets.all(14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              SegmentedButton<Sex>(
                segments: const <ButtonSegment<Sex>>[
                  ButtonSegment<Sex>(value: Sex.male, label: Text('Male')),
                  ButtonSegment<Sex>(value: Sex.female, label: Text('Female')),
                ],
                selected: <Sex>{_sex},
                onSelectionChanged: (Set<Sex> selection) =>
                    setState(() => _sex = selection.first),
              ),
              SegmentedButton<WeightUnit>(
                segments: const <ButtonSegment<WeightUnit>>[
                  ButtonSegment<WeightUnit>(
                      value: WeightUnit.lb, label: Text('lb / ft')),
                  ButtonSegment<WeightUnit>(
                      value: WeightUnit.kg, label: Text('kg / cm')),
                ],
                selected: <WeightUnit>{_unit},
                onSelectionChanged: (Set<WeightUnit> selection) =>
                    _changeUnits(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _field(_age, 'Age', 80, decimal: false),
              _field(_weight, 'Weight', 110, suffix: _weightUnit),
              if (_heightUnit == HeightUnit.cm)
                _field(_cm, 'Height', 110, suffix: 'cm')
              else ...<Widget>[
                _field(_ft, 'Height', 90, suffix: 'ft', decimal: false),
                _field(_inch, 'Inches', 90, suffix: 'in'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ActivityLevel>(
            initialValue: _activity,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Activity level'),
            items: <DropdownMenuItem<ActivityLevel>>[
              for (final ActivityLevel activity in ActivityLevel.values)
                DropdownMenuItem<ActivityLevel>(
                  value: activity,
                  child: Text('${activity.label} — ${activity.description}'),
                ),
            ],
            onChanged: (ActivityLevel? value) {
              if (value != null) setState(() => _activity = value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Mifflin–St Jeor estimate with common activity multipliers. '
            'Activity is approximate; your details are not saved.',
            style: text.bodySmall,
          ),
          Text(
            'Use the estimate to fill your calorie goal, then save it with Save goals.',
            style: text.bodySmall,
          ),
          const Divider(height: 24),
          if (estimate == null)
            Text(estimateMessage!, style: text.bodySmall)
          else ...<Widget>[
            Text(
              'BMR: ${fmtNum(roundKcal(estimate.bmr.kcal, step: 1).toDouble(), decimals: 0)} calories/day',
              style: text.bodyMedium,
            ),
            Text(
              'TDEE: ${fmtNum(roundKcal(estimate.tdee, step: 1).toDouble(), decimals: 0)} calories/day',
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => widget.onUse(roundKcal(estimate!.tdee, step: 1)),
              child: const Text('Use estimate'),
            ),
          ],
        ],
      ),
    );
  }
}
