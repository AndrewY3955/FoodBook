import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../data/energy_model.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../state/nutrition_controllers.dart';
import 'nutrition_widgets.dart';

/// Maintenance-calorie calculator for the Goals tab. Combines a formula
/// estimate with the user's own diary and weigh-ins, and says how much to
/// trust the result.
class MaintenanceCalculator extends ConsumerStatefulWidget {
  const MaintenanceCalculator({super.key, required this.onUse});

  /// Called with the calorie target the user chose to adopt.
  final ValueChanged<int> onUse;

  @override
  ConsumerState<MaintenanceCalculator> createState() =>
      _MaintenanceCalculatorState();
}

class _MaintenanceCalculatorState extends ConsumerState<MaintenanceCalculator> {
  bool _loaded = false;
  bool _saving = false;
  Sex _sex = Sex.male;
  WeightUnit _unit = WeightUnit.lb;
  HeightUnit _heightUnit = HeightUnit.feetInches;
  ActivityLevel _activity = ActivityLevel.sedentary;
  int _goalDelta = 0;

  final TextEditingController _age = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _cm = TextEditingController();
  final TextEditingController _ft = TextEditingController();
  final TextEditingController _inch = TextEditingController();
  final TextEditingController _weighIn = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _age,
      _weight,
      _cm,
      _ft,
      _inch,
      _weighIn,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _unitLabel => _unit == WeightUnit.kg ? 'kg' : 'lb';

  String _showWeight(double kg) =>
      fmtNum(_unit == WeightUnit.kg ? kg : kg / kgPerLb);

  void _fill(BodyProfile p) {
    _sex = p.sex;
    _unit = p.weightUnit;
    _activity = p.activity;
    _age.text = '${p.ageYears}';
    _weight.text = _showWeight(p.weightKg);
    _cm.text = fmtNum(p.heightCm);
    final double totalIn = p.heightCm / cmPerInch;
    _ft.text = '${totalIn ~/ 12}';
    _inch.text = fmtNum(totalIn - (totalIn ~/ 12) * 12);
    _heightUnit =
        p.weightUnit == WeightUnit.kg ? HeightUnit.cm : HeightUnit.feetInches;
  }

  double _num(TextEditingController c, String what) {
    final double? v = double.tryParse(c.text.trim());
    if (v == null) throw EnergyInputError('Enter your $what.');
    return v;
  }

  /// Throws [EnergyInputError] with a user-readable message.
  BodyProfile _readProfile() {
    final double age = _num(_age, 'age');
    final double kg = weightToKg(_num(_weight, 'weight'), _unit);
    final double cm = _heightUnit == HeightUnit.cm
        ? heightToCm(HeightUnit.cm, _num(_cm, 'height'))
        : heightToCm(HeightUnit.feetInches, _num(_ft, 'height (feet)'),
            inches: _inch.text.trim().isEmpty ? 0 : _num(_inch, 'height'));
    final BodyProfile p = BodyProfile(
      sex: _sex,
      ageYears: age.round(),
      heightCm: cm,
      weightKg: kg,
      activity: _activity,
      equation: BmrEquation.mifflinStJeor,
      weightUnit: _unit,
    );
    p.toEnergyProfile();
    return p;
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveProfile() async {
    try {
      final BodyProfile p = _readProfile();
      setState(() => _saving = true);
      await ref.read(nutritionRepositoryProvider).saveBodyProfile(p);
      ref.invalidate(bodyProfileProvider);
      if (mounted) _toast('Profile saved.');
    } on EnergyInputError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(Failure.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logWeighIn() async {
    final double? v = double.tryParse(_weighIn.text.trim());
    if (v == null) {
      _toast('Enter your weight.');
      return;
    }
    try {
      await ref
          .read(nutritionRepositoryProvider)
          .saveWeighIn(DateTime.now(), weightToKg(v, _unit));
      _weighIn.clear();
      ref.invalidate(weighInsProvider);
    } on EnergyInputError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(Failure.from(e).message);
    }
  }

  Future<void> _deleteWeighIn(DateTime day) async {
    try {
      await ref.read(nutritionRepositoryProvider).deleteWeighIn(day);
      ref.invalidate(weighInsProvider);
    } catch (e) {
      _toast(Failure.from(e).message);
    }
  }

  List<DailyIntake> _intakes(List<FoodLogEntry> log) {
    final Map<String, double> kcal = <String, double>{};
    final Map<String, DateTime> days = <String, DateTime>{};
    for (final FoodLogEntry e in log) {
      final String k = dayKey(e.day);
      kcal[k] = (kcal[k] ?? 0) + (e.nutrition.calories ?? 0);
      days[k] = e.day;
    }
    return <DailyIntake>[
      for (final MapEntry<String, double> e in kcal.entries)
        DailyIntake(days[e.key]!, e.value),
    ];
  }

  Widget _field(TextEditingController c, String label, double width,
          {String? suffix, bool decimal = true}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: label, suffixText: suffix, isDense: true),
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
                RegExp(decimal ? r'[0-9.]' : r'[0-9]')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BodyProfile?> saved = ref.watch(bodyProfileProvider);
    final List<WeighIn> weighIns =
        ref.watch(weighInsProvider).valueOrNull ?? const <WeighIn>[];
    final List<FoodLogEntry> log =
        ref.watch(foodLogProvider).valueOrNull ?? const <FoodLogEntry>[];

    if (!_loaded && saved.hasValue) {
      _loaded = true;
      final BodyProfile? p = saved.value;
      if (p != null) _fill(p);
    }

    final TextTheme text = Theme.of(context).textTheme;
    BodyProfile? profile;
    String? profileError;
    try {
      profile = _readProfile();
    } on EnergyInputError catch (e) {
      profileError = e.message;
    }

    MaintenanceEstimate? est;
    if (profile != null) {
      est = estimateMaintenance(
        profile.toEnergyProfile(),
        _intakes(log),
        weighIns,
        DateTime.now(),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: const Text('Maintenance calories'),
        subtitle: const Text(
            'Estimate what you burn, then refine it with your own data'),
        childrenPadding: const EdgeInsets.all(14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(spacing: 12, runSpacing: 8, children: <Widget>[
            SegmentedButton<Sex>(
              segments: const <ButtonSegment<Sex>>[
                ButtonSegment<Sex>(value: Sex.male, label: Text('Male')),
                ButtonSegment<Sex>(value: Sex.female, label: Text('Female')),
              ],
              selected: <Sex>{_sex},
              onSelectionChanged: (Set<Sex> s) =>
                  setState(() => _sex = s.first),
            ),
            SegmentedButton<WeightUnit>(
              segments: const <ButtonSegment<WeightUnit>>[
                ButtonSegment<WeightUnit>(
                    value: WeightUnit.lb, label: Text('lb / ft')),
                ButtonSegment<WeightUnit>(
                    value: WeightUnit.kg, label: Text('kg / cm')),
              ],
              selected: <WeightUnit>{_unit},
              onSelectionChanged: (Set<WeightUnit> s) {
                final WeightUnit next = s.first;
                final double? w = double.tryParse(_weight.text.trim());
                setState(() {
                  if (w != null) {
                    final double kg = weightToKg(w, _unit);
                    _weight.text =
                        fmtNum(next == WeightUnit.kg ? kg : kg / kgPerLb);
                  }
                  _unit = next;
                  _heightUnit = next == WeightUnit.kg
                      ? HeightUnit.cm
                      : HeightUnit.feetInches;
                });
              },
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            _field(_age, 'Age', 80, decimal: false),
            _field(_weight, 'Weight', 110, suffix: _unitLabel),
            if (_heightUnit == HeightUnit.cm)
              _field(_cm, 'Height', 110, suffix: 'cm')
            else ...<Widget>[
              _field(_ft, 'Height', 90, suffix: 'ft', decimal: false),
              _field(_inch, 'Inches', 90, suffix: 'in'),
            ],
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<ActivityLevel>(
            key: ValueKey<ActivityLevel>(_activity),
            initialValue: _activity,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Activity level'),
            items: <DropdownMenuItem<ActivityLevel>>[
              for (final ActivityLevel a in ActivityLevel.values)
                DropdownMenuItem<ActivityLevel>(
                  value: a,
                  child: Text('${a.label} — ${a.description}'),
                ),
            ],
            onChanged: (ActivityLevel? v) =>
                setState(() => _activity = v ?? _activity),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This is a conservative starting estimate, not a medical '
              'measurement; your actual maintenance can differ.',
              style: text.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Using Mifflin–St Jeor, a commonly used adult resting-energy '
              'equation. It estimates resting needs; the activity adjustment '
              'is approximate.',
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _saving ? null : _saveProfile,
              child: Text(_saving ? 'Saving…' : 'Save my details'),
            ),
          ),
          const Divider(height: 28),
          Text('Weigh-ins', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Weigh yourself in the morning a few times a week. The estimate '
            'learns from your weight trend and your food diary.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _field(_weighIn, 'Today', 120, suffix: _unitLabel),
                FilledButton.tonal(
                    onPressed: _logWeighIn, child: const Text('Log weight')),
              ]),
          if (weighIns.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 0, children: <Widget>[
              for (final WeighIn w in weighIns.reversed.take(6))
                InputChip(
                  label: Text(
                      '${w.day.month}/${w.day.day}  ${_showWeight(w.kg)} $_unitLabel'),
                  onDeleted: () => _deleteWeighIn(w.day),
                ),
            ]),
          const Divider(height: 28),
          if (est == null)
            Text(profileError ?? 'Fill in your details.',
                style: TextStyle(color: Theme.of(context).colorScheme.error))
          else
            ..._result(context, est, profile!, weighIns),
        ],
      ),
    );
  }

  List<Widget> _result(BuildContext context, MaintenanceEstimate est,
      BodyProfile profile, List<WeighIn> weighIns) {
    final TextTheme text = Theme.of(context).textTheme;
    final CalibrationResult c = est.calibration;
    final int maintenance = roundKcal(est.recommended, step: 50);
    final int target = (maintenance + _goalDelta).clamp(1200, 6000);
    final double? unc = c.uncertaintyKcal;

    String? projection;
    if (_goalDelta != 0) {
      try {
        final List<ProjectionPoint> pts = projectWeight(
          profile: est.profile,
          maintenanceKcal: est.recommended,
          intakeKcal: target.toDouble(),
          days: 84,
        );
        final double change = pts.last.weightKg - pts.first.weightKg;
        final double shown = _unit == WeightUnit.kg ? change : change / kgPerLb;
        projection = 'Roughly ${shown >= 0 ? '+' : '-'}${fmtNum(shown.abs())} '
            '$_unitLabel after 12 weeks, slowing as your body adjusts. A guide, not a promise.';
      } on EnergyInputError {
        projection = null;
      }
    }

    return <Widget>[
      Text('About $maintenance calories a day to maintain weight',
          style: text.titleMedium),
      const SizedBox(height: 4),
      Text(est.method, style: text.bodySmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
        Chip(
            label: Text(
                'Formula: ${roundKcal(est.formula.tdee, step: 50)} (BMR ${roundKcal(est.formula.bmr.kcal, step: 50)} x ${est.formula.factor})')),
        if (c.empiricalTdee != null)
          Chip(
              label: Text(
                  'From your data: ${roundKcal(c.empiricalTdee!, step: 50)}'
                  '${unc == null ? '' : ' ± ${roundKcal(unc, step: 50)}'}')),
        Chip(label: Text('Tracking-data signal: ${c.confidence.label}')),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'These are estimates, not clinical measurements. Mifflin-St Jeor '
          'predicts resting energy; the activity multiplier only approximates '
          'total daily needs. The tracking-data signal is an app heuristic, '
          'not a clinically validated confidence level. Your data estimate '
          'uses reported food and scale entries, so missed food and fluid '
          'changes can affect it. The ± value reflects weight-trend scatter '
          'only, not total uncertainty or a clinical confidence interval. '
          'For medical nutrition needs, consult a clinician or dietitian; '
          'indirect calorimetry can measure resting energy expenditure.',
          style: text.bodySmall,
        ),
      ),
      for (final String r in <String>[
        ...c.reasons,
        ...est.flags,
        ...est.formula.bmr.notes
      ])
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('• $r', style: text.bodySmall),
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey<int>(_goalDelta),
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
      if (projection != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(projection, style: text.bodySmall),
        ),
      const SizedBox(height: 12),
      Row(children: <Widget>[
        Expanded(
          child: Text('Calorie goal: $target a day', style: text.titleMedium),
        ),
        FilledButton.tonal(
          onPressed: () => widget.onUse(target),
          child: const Text('Use this'),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
        'An estimate, not a measurement or medical advice. Individual '
        'metabolism varies by a couple of hundred calories either way.',
        style: text.bodySmall,
      ),
    ];
  }
}
