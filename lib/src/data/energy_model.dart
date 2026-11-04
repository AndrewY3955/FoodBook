import 'dart:math' as math;

/// Maintenance-calorie (TDEE) estimation.
///
/// Three layers, kept separate on purpose:
///  1. A formula estimate: resting equation x activity factor.
///  2. An empirical estimate from logged intake and weigh-ins.
///  3. A recommendation that moves from (1) toward (2) only as far as the
///     quality of the tracking justifies.
///
/// Nothing here is a measured metabolic rate. Every value is an estimate.
/// All maths is full precision; use [roundKcal] only for display.
///
/// References: Mifflin et al. 1990 (Am J Clin Nutr 51:241); Frankenfield et
/// al. 2005 (J Am Diet Assoc 105:775); Roza & Shizgal 1984 (revised
/// Harris-Benedict); Cunningham 1980; ten Haaf & Weijs 2014 (PLoS ONE
/// 9:e108460); Hall et al. 2011 (Lancet 378:826) for the dynamic model.

enum Sex { male, female }

enum WeightUnit { kg, lb }

enum HeightUnit { cm, inch, feetInches }

const double kgPerLb = 0.45359237;
const double cmPerInch = 2.54;

/// Approximate energy density of body-weight change. Not a constant of
/// nature: the true figure depends on the lean/fat mix of the change.
const double kDefaultKcalPerKg = 7700;

class EnergyInputError implements Exception {
  const EnergyInputError(this.message);
  final String message;
  @override
  String toString() => message;
}

double weightToKg(double value, WeightUnit unit) {
  _finite(value, 'Weight');
  return unit == WeightUnit.kg ? value : value * kgPerLb;
}

/// [value] is cm, inches, or the feet part; [inches] only applies to
/// [HeightUnit.feetInches].
double heightToCm(HeightUnit unit, double value, {double inches = 0}) {
  _finite(value, 'Height');
  _finite(inches, 'Height');
  if (inches < 0 || inches >= 12 && unit == HeightUnit.feetInches) {
    throw const EnergyInputError('Inches must be between 0 and 11.9.');
  }
  switch (unit) {
    case HeightUnit.cm:
      return value;
    case HeightUnit.inch:
      return value * cmPerInch;
    case HeightUnit.feetInches:
      return (value * 12 + inches) * cmPerInch;
  }
}

void _finite(double v, String what) {
  if (v.isNaN || v.isInfinite) {
    throw EnergyInputError('$what must be a number.');
  }
}

enum BmrEquation {
  mifflinStJeor(
    'Mifflin-St Jeor',
    'Default for adults. Validated against indirect calorimetry in '
        'healthy, non-obese and obese adults (Mifflin 1990; Frankenfield 2005).',
  ),
  revisedHarrisBenedict(
    'Revised Harris-Benedict',
    'Roza & Shizgal 1984 revision. A comparison estimate; it tends to run '
        'slightly higher than Mifflin-St Jeor.',
  ),
  cunningham(
    'Cunningham',
    'Uses fat-free mass, so it needs a body-fat percentage. Best for lean or '
        'athletic people with a reliable body-fat measurement.',
  ),
  tenHaaf(
    'ten Haaf (athletes)',
    'Weight-based equation derived in recreational athletes aged 18 to 35. '
        'Do not use it for the general population.',
  );

  const BmrEquation(this.label, this.description);
  final String label;
  final String description;
}

/// Conventional activity multipliers used by many TDEE calculators.
/// These are rough heuristics, not clinically validated standards.
enum ActivityLevel {
  sedentary(1.2, 'Not active', 'Little to no exercise'),
  light(1.375, 'Lightly active', 'Light exercise 1-3 days/week'),
  moderate(1.55, 'Moderately active', 'Moderate exercise 3-5 days/week'),
  very(1.725, 'Very active', 'Hard exercise 5-6 days/week'),
  extreme(1.9, 'Extremely active', 'Hard exercise 6-7 days/week');

  const ActivityLevel(this.factor, this.label, this.description);
  final double factor;
  final String label;
  final String description;
}

enum WeightGoal { maintain, lose, gain }

/// Converts a weekly weight-change goal into a daily calorie target.
///
/// Uses the approximate energy density of [kDefaultKcalPerKg]. This is a
/// static estimate and does not model metabolic adaptation over time.
double dailyCalorieGoal({
  required double maintenanceKcal,
  required WeightGoal goal,
  double weeklyChangeKg = 0,
}) {
  _finite(maintenanceKcal, 'Maintenance calories');
  _finite(weeklyChangeKg, 'Weekly weight change');
  if (maintenanceKcal <= 0) {
    throw const EnergyInputError('Maintenance calories must be above zero.');
  }
  if (goal != WeightGoal.maintain && weeklyChangeKg <= 0) {
    throw const EnergyInputError(
        'Weekly weight change must be above zero for loss or gain.');
  }
  if (weeklyChangeKg < 0) {
    throw const EnergyInputError('Weekly weight change cannot be negative.');
  }
  final double dailyAdjustment = weeklyChangeKg * kDefaultKcalPerKg / 7;
  final double target = switch (goal) {
    WeightGoal.maintain => maintenanceKcal,
    WeightGoal.lose => maintenanceKcal - dailyAdjustment,
    WeightGoal.gain => maintenanceKcal + dailyAdjustment,
  };
  _finite(target, 'Daily calorie target');
  if (target <= 0) {
    throw const EnergyInputError(
        'This weekly loss goal results in a daily target at or below zero.');
  }
  return target;
}

class EnergyProfile {
  EnergyProfile._({
    required this.sex,
    required this.ageYears,
    required this.weightKg,
    required this.heightCm,
    required this.activity,
    required this.equation,
    this.bodyFatPercent,
    this.bodyFatMeasured = false,
  });

  /// Validates every input. Throws [EnergyInputError] with a user-readable
  /// message instead of silently clamping.
  factory EnergyProfile({
    required Sex sex,
    required double ageYears,
    required double weightKg,
    required double heightCm,
    ActivityLevel activity = ActivityLevel.sedentary,
    BmrEquation equation = BmrEquation.mifflinStJeor,
    double? bodyFatPercent,
    bool bodyFatMeasured = false,
  }) {
    _finite(ageYears, 'Age');
    _finite(weightKg, 'Weight');
    _finite(heightCm, 'Height');
    if (ageYears < 18 || ageYears > 100) {
      throw const EnergyInputError(
          'These equations are for adults aged 18 to 100.');
    }
    if (weightKg < 30 || weightKg > 400) {
      throw const EnergyInputError(
          'Weight must be between 30 kg (66 lb) and 400 kg (882 lb).');
    }
    if (heightCm < 120 || heightCm > 230) {
      throw const EnergyInputError(
          'Height must be between 120 cm (3 ft 11 in) and 230 cm (7 ft 7 in).');
    }
    if (bodyFatPercent != null) {
      _finite(bodyFatPercent, 'Body fat');
      if (bodyFatPercent < 3 || bodyFatPercent > 65) {
        throw const EnergyInputError('Body fat must be between 3% and 65%.');
      }
    }
    if (equation == BmrEquation.cunningham && bodyFatPercent == null) {
      throw const EnergyInputError(
          'The Cunningham equation needs a body-fat percentage.');
    }
    return EnergyProfile._(
      sex: sex,
      ageYears: ageYears,
      weightKg: weightKg,
      heightCm: heightCm,
      activity: activity,
      equation: equation,
      bodyFatPercent: bodyFatPercent,
      bodyFatMeasured: bodyFatMeasured && bodyFatPercent != null,
    );
  }

  final Sex sex;
  final double ageYears;
  final double weightKg;
  final double heightCm;
  final ActivityLevel activity;
  final BmrEquation equation;
  final double? bodyFatPercent;

  /// True only when the body-fat figure came from a measurement (DEXA,
  /// calipers by a professional, bioimpedance) rather than a guess.
  final bool bodyFatMeasured;

  EnergyProfile copyWith({
    double? weightKg,
    ActivityLevel? activity,
    BmrEquation? equation,
    double? ageYears,
  }) =>
      EnergyProfile(
        sex: sex,
        ageYears: ageYears ?? this.ageYears,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm,
        activity: activity ?? this.activity,
        equation: equation ?? this.equation,
        bodyFatPercent: bodyFatPercent,
        bodyFatMeasured: bodyFatMeasured,
      );

  double? get fatFreeMassKg =>
      bodyFatPercent == null ? null : weightKg * (1 - bodyFatPercent! / 100);
}

class BmrResult {
  const BmrResult(this.kcal, this.equation, this.notes);
  final double kcal;
  final BmrEquation equation;
  final List<String> notes;
}

BmrResult computeBmr(EnergyProfile p) {
  final bool male = p.sex == Sex.male;
  final List<String> notes = <String>[];
  double kcal;
  switch (p.equation) {
    case BmrEquation.mifflinStJeor:
      kcal = 10 * p.weightKg +
          6.25 * p.heightCm -
          5 * p.ageYears +
          (male ? 5 : -161);
      if (p.ageYears < 19 || p.ageYears > 78) {
        notes.add('Mifflin-St Jeor was validated for ages 19 to 78.');
      }
    case BmrEquation.revisedHarrisBenedict:
      kcal = male
          ? 88.362 +
              13.397 * p.weightKg +
              4.799 * p.heightCm -
              5.677 * p.ageYears
          : 447.593 +
              9.247 * p.weightKg +
              3.098 * p.heightCm -
              4.330 * p.ageYears;
    case BmrEquation.cunningham:
      kcal = 500 + 22 * p.fatFreeMassKg!;
      if (!p.bodyFatMeasured) {
        notes.add(
            'Body fat is your own estimate, so this result is only as good as that guess.');
      }
    case BmrEquation.tenHaaf:
      kcal = 11.936 * p.weightKg +
          587.728 * (p.heightCm / 100) -
          8.129 * p.ageYears +
          (male ? 191.027 : 0) +
          29.279;
      if (p.ageYears < 18 || p.ageYears > 35) {
        notes.add(
            'Derived in athletes aged 18 to 35; less reliable outside it.');
      }
  }
  return BmrResult(kcal, p.equation, notes);
}

class FormulaEstimate {
  const FormulaEstimate(this.bmr, this.tdee, this.factor);
  final BmrResult bmr;
  final double tdee;
  final double factor;
}

/// TDEE = BMR x activity factor.
FormulaEstimate formulaTdee(EnergyProfile p) {
  final BmrResult b = computeBmr(p);
  return FormulaEstimate(b, b.kcal * p.activity.factor, p.activity.factor);
}

/// Display rounding. Never feed the result back into calculations.
int roundKcal(double v, {int step = 25}) => (v / step).round() * step;

// ---------------------------------------------------------------------
// Empirical calibration
// ---------------------------------------------------------------------

class DailyIntake {
  const DailyIntake(this.day, this.kcal);
  final DateTime day;
  final double kcal;
}

class WeighIn {
  const WeighIn(this.day, this.kg);
  final DateTime day;
  final double kg;
}

enum Confidence {
  insufficient('Not enough data'),
  low('Low'),
  moderate('Moderate'),
  high('High');

  const Confidence(this.label);
  final String label;
}

class CalibrationConfig {
  const CalibrationConfig({
    this.windowDays = 28,
    this.minTrackedDays = 21,
    this.minWeighIns = 8,
    this.minIntakeCoverage = 0.6,
    this.minLoggedDayKcal = 600,
    this.kcalPerKg = kDefaultKcalPerKg,
    this.maxBlend = 0.8,
    this.maxDeviation = 0.35,
    this.maxStepKcal = 100,
  });

  final int windowDays;
  final int minTrackedDays;
  final int minWeighIns;
  final double minIntakeCoverage;

  /// A day logged below this is treated as an incomplete log and ignored,
  /// never averaged in as a real very-low-calorie day.
  final double minLoggedDayKcal;
  final double kcalPerKg;

  /// Most the recommendation may move toward the empirical figure.
  final double maxBlend;

  /// Empirical results further than this fraction from the formula are
  /// capped and flagged as probably a logging error.
  final double maxDeviation;

  /// Largest change to the recommendation per update.
  final double maxStepKcal;
}

class CalibrationResult {
  const CalibrationResult({
    required this.confidence,
    required this.reasons,
    this.empiricalTdee,
    this.averageIntake,
    this.slopeKgPerDay,
    this.uncertaintyKcal,
    this.trackedDays = 0,
    this.intakeDays = 0,
    this.weighIns = 0,
    this.intakeCoverage = 0,
    this.blend = 0,
  });

  final Confidence confidence;

  /// Plain-language reasons the estimate is limited or unavailable.
  final List<String> reasons;
  final double? empiricalTdee;
  final double? averageIntake;
  final double? slopeKgPerDay;

  /// Rough one-sigma error from weight scatter alone. Food-logging error is
  /// not included, so real uncertainty is larger.
  final double? uncertaintyKcal;
  final int trackedDays;
  final int intakeDays;
  final int weighIns;
  final double intakeCoverage;

  /// 0..1 share of the formula-to-empirical gap the recommendation closes.
  final double blend;

  bool get usable => confidence != Confidence.insufficient;
}

DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int _daysBetween(DateTime a, DateTime b) =>
    dateOnly(b).difference(dateOnly(a)).inDays;

double _median(List<double> v) {
  final List<double> s = List<double>.of(v)..sort();
  final int n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Median of the last [days] weigh-ins up to [asOf]; falls back to the most
/// recent weigh-in within 30 days. Null when there is nothing recent.
double? smoothedWeightKg(List<WeighIn> weighIns, DateTime asOf,
    {int days = 7}) {
  final DateTime end = dateOnly(asOf);
  final List<WeighIn> upTo = weighIns
      .where((WeighIn w) => !dateOnly(w.day).isAfter(end))
      .toList()
    ..sort((WeighIn a, WeighIn b) => a.day.compareTo(b.day));
  if (upTo.isEmpty) return null;
  final List<double> recent = upTo
      .where((WeighIn w) => _daysBetween(w.day, end) < days)
      .map((WeighIn w) => w.kg)
      .toList();
  if (recent.isNotEmpty) return _median(recent);
  return _daysBetween(upTo.last.day, end) <= 30 ? upTo.last.kg : null;
}

/// Estimates maintenance from what actually happened to weight.
///
/// TDEE = average logged intake - kcalPerKg x (weight change per day).
/// The weight trend is a Theil-Sen slope over pairs of weigh-ins at least a
/// week apart, so a single water-weight spike barely moves it. Days with no
/// log are skipped, not counted as zero.
CalibrationResult calibrate(
  List<DailyIntake> intakes,
  List<WeighIn> weighIns,
  DateTime asOf, {
  CalibrationConfig config = const CalibrationConfig(),
}) {
  final DateTime end = dateOnly(asOf);
  final DateTime start = end.subtract(Duration(days: config.windowDays - 1));
  bool inWindow(DateTime d) {
    final DateTime x = dateOnly(d);
    return !x.isBefore(start) && !x.isAfter(end);
  }

  // One value per day: mean of multiple weigh-ins; sum of multiple log rows.
  final Map<DateTime, List<double>> w = <DateTime, List<double>>{};
  for (final WeighIn x in weighIns) {
    if (!inWindow(x.day) || x.kg.isNaN || x.kg <= 0) continue;
    w.putIfAbsent(dateOnly(x.day), () => <double>[]).add(x.kg);
  }
  final Map<DateTime, double> intakeByDay = <DateTime, double>{};
  for (final DailyIntake x in intakes) {
    if (!inWindow(x.day) || x.kcal.isNaN) continue;
    intakeByDay.update(dateOnly(x.day), (double v) => v + x.kcal,
        ifAbsent: () => x.kcal);
  }

  final List<DateTime> weighDays = w.keys.toList()..sort();
  final List<String> reasons = <String>[];
  if (weighDays.length < 2) {
    return CalibrationResult(
      confidence: Confidence.insufficient,
      reasons: <String>['Log your weight a few times a week to calibrate.'],
      weighIns: weighDays.length,
    );
  }
  final DateTime first = weighDays.first;
  final DateTime last = weighDays.last;
  final int tracked = _daysBetween(first, last) + 1;

  final List<double> loggedKcal = <double>[];
  intakeByDay.forEach((DateTime d, double kcal) {
    if (!d.isBefore(first) &&
        !d.isAfter(last) &&
        kcal >= config.minLoggedDayKcal) {
      loggedKcal.add(kcal);
    }
  });
  final double coverage = loggedKcal.length / tracked;

  CalibrationResult insufficient(String reason) => CalibrationResult(
        confidence: Confidence.insufficient,
        reasons: <String>[...reasons, reason],
        trackedDays: tracked,
        intakeDays: loggedKcal.length,
        weighIns: weighDays.length,
        intakeCoverage: coverage,
      );

  if (tracked < config.minTrackedDays) {
    return insufficient(
        'Only $tracked days tracked. At least ${config.minTrackedDays} are needed, and 28 or more is better.');
  }
  if (weighDays.length < config.minWeighIns) {
    return insufficient(
        'Only ${weighDays.length} weigh-ins. Aim for at least ${config.minWeighIns}, ideally most mornings.');
  }
  if (coverage < config.minIntakeCoverage) {
    return insufficient(
        'Food was logged on ${(coverage * 100).round()}% of days. At least ${(config.minIntakeCoverage * 100).round()}% is needed.');
  }

  final List<double> xs = <double>[
    for (final DateTime d in weighDays) _daysBetween(first, d).toDouble()
  ];
  final List<double> ys = <double>[
    for (final DateTime d in weighDays)
      w[d]!.reduce((double a, double b) => a + b) / w[d]!.length
  ];

  final List<double> slopes = <double>[];
  for (int i = 0; i < xs.length; i++) {
    for (int j = i + 1; j < xs.length; j++) {
      if (xs[j] - xs[i] >= 7) slopes.add((ys[j] - ys[i]) / (xs[j] - xs[i]));
    }
  }
  if (slopes.isEmpty) {
    return insufficient('Weigh-ins are too close together to show a trend.');
  }
  final double slope = _median(slopes);
  final double intercept = _median(
      <double>[for (int i = 0; i < xs.length; i++) ys[i] - slope * xs[i]]);
  final double sigma = math.max(
    1.4826 *
        _median(<double>[
          for (int i = 0; i < xs.length; i++)
            (ys[i] - (intercept + slope * xs[i])).abs()
        ]),
    0.3, // floor: a scale is never exact, and tidy data should not look exact
  );
  final double meanX = xs.reduce((double a, double b) => a + b) / xs.length;
  final double sxx =
      xs.fold<double>(0, (double s, double x) => s + (x - meanX) * (x - meanX));
  final double uncertainty = config.kcalPerKg * sigma / math.sqrt(sxx);

  final double avgIntake =
      loggedKcal.reduce((double a, double b) => a + b) / loggedKcal.length;
  final double empirical = avgIntake - config.kcalPerKg * slope;

  final bool daily28 = tracked >= 28;
  Confidence level;
  if (daily28 &&
      coverage >= 0.85 &&
      weighDays.length >= 12 &&
      uncertainty <= 150) {
    level = Confidence.high;
  } else if (coverage >= 0.7 && uncertainty <= 300) {
    level = Confidence.moderate;
  } else {
    level = Confidence.low;
  }
  if (tracked < 28) {
    reasons.add('28 or more tracked days gives a steadier result.');
  }
  if (coverage < 0.85) reasons.add('Logging more days improves accuracy.');
  if (uncertainty > 150) {
    reasons.add('Your weigh-ins vary a lot, which widens the estimate.');
  }

  return CalibrationResult(
    confidence: level,
    reasons: reasons,
    empiricalTdee: empirical,
    averageIntake: avgIntake,
    slopeKgPerDay: slope,
    uncertaintyKcal: uncertainty,
    trackedDays: tracked,
    intakeDays: loggedKcal.length,
    weighIns: weighDays.length,
    intakeCoverage: coverage,
    blend: switch (level) {
      Confidence.high => math.min(config.maxBlend, 0.8),
      Confidence.moderate => math.min(config.maxBlend, 0.5),
      Confidence.low => math.min(config.maxBlend, 0.25),
      Confidence.insufficient => 0,
    },
  );
}

class MaintenanceEstimate {
  const MaintenanceEstimate({
    required this.profile,
    required this.formula,
    required this.calibration,
    required this.recommended,
    required this.usedEmpirical,
    this.flags = const <String>[],
  });

  /// Profile with the weight actually used (smoothed recent weigh-ins).
  final EnergyProfile profile;

  /// 1. Initial formula-based estimate, always preserved.
  final FormulaEstimate formula;

  /// 2. Empirical estimate and its data quality.
  final CalibrationResult calibration;

  /// 3. Current recommendation: formula moved toward empirical by a
  /// confidence-based share, and rate-limited.
  final double recommended;
  final bool usedEmpirical;
  final List<String> flags;

  String get method => usedEmpirical
      ? '${formula.bmr.equation.label} x activity, adjusted toward your logged data'
      : '${formula.bmr.equation.label} x ${profile.activity.label.toLowerCase()} (${formula.factor})';
}

MaintenanceEstimate estimateMaintenance(
  EnergyProfile profile,
  List<DailyIntake> intakes,
  List<WeighIn> weighIns,
  DateTime asOf, {
  double? previousRecommended,
  CalibrationConfig config = const CalibrationConfig(),
}) {
  // Maintenance moves with body weight, so the formula uses the current
  // smoothed weight rather than whatever was typed in once.
  final double? current = smoothedWeightKg(weighIns, asOf);
  final EnergyProfile p = current == null || current < 30 || current > 400
      ? profile
      : profile.copyWith(weightKg: current);
  final FormulaEstimate f = formulaTdee(p);
  final CalibrationResult c =
      calibrate(intakes, weighIns, asOf, config: config);
  final List<String> flags = <String>[];

  double target = f.tdee;
  bool used = false;
  if (c.usable && c.empiricalTdee != null) {
    final double lo = f.tdee * (1 - config.maxDeviation);
    final double hi = f.tdee * (1 + config.maxDeviation);
    double e = c.empiricalTdee!;
    double blend = c.blend;
    if (e < lo || e > hi) {
      e = e.clamp(lo, hi).toDouble();
      blend = blend / 2;
      flags.add(
          'Your logged data points to a very different maintenance than the formula. Check for missed meals or inaccurate weights.');
    }
    target = f.tdee + blend * (e - f.tdee);
    used = blend > 0;
  }
  if (previousRecommended != null) {
    target = target
        .clamp(previousRecommended - config.maxStepKcal,
            previousRecommended + config.maxStepKcal)
        .toDouble();
  }
  return MaintenanceEstimate(
    profile: p,
    formula: f,
    calibration: c,
    recommended: target,
    usedEmpirical: used,
    flags: flags,
  );
}

class HistoryPoint {
  const HistoryPoint(this.day, this.estimate);
  final DateTime day;
  final MaintenanceEstimate estimate;
}

/// Replays the estimate at weekly steps so progress is visible. Each step
/// only sees data up to its own date, and each recommendation can move at
/// most [CalibrationConfig.maxStepKcal] from the previous one.
List<HistoryPoint> maintenanceHistory(
  EnergyProfile profile,
  List<DailyIntake> intakes,
  List<WeighIn> weighIns,
  DateTime asOf, {
  int points = 8,
  int stepDays = 7,
  CalibrationConfig config = const CalibrationConfig(),
}) {
  final List<HistoryPoint> out = <HistoryPoint>[];
  double? previous;
  for (int i = points - 1; i >= 0; i--) {
    final DateTime day = dateOnly(asOf).subtract(Duration(days: i * stepDays));
    final MaintenanceEstimate e = estimateMaintenance(
      profile,
      intakes.where((DailyIntake x) => !dateOnly(x.day).isAfter(day)).toList(),
      weighIns.where((WeighIn x) => !dateOnly(x.day).isAfter(day)).toList(),
      day,
      previousRecommended: previous,
      config: config,
    );
    previous = e.recommended;
    out.add(HistoryPoint(day, e));
  }
  return out;
}

// ---------------------------------------------------------------------
// Dynamic weight projection
// ---------------------------------------------------------------------

/// Deurenberg et al. 1991. Only used when the user gave no body fat.
double estimateBodyFatPercent(EnergyProfile p) {
  final double bmi = p.weightKg / math.pow(p.heightCm / 100, 2);
  return (1.2 * bmi +
          0.23 * p.ageYears -
          10.8 * (p.sex == Sex.male ? 1 : 0) -
          5.4)
      .clamp(5, 60)
      .toDouble();
}

class ProjectionPoint {
  const ProjectionPoint(this.day, this.weightKg, this.maintenanceKcal);
  final int day;
  final double weightKg;
  final double maintenanceKcal;
}

/// Day-by-day projection with a simplified two-compartment energy-balance
/// model in the style of Hall et al. 2011 (the basis of the NIDDK Body
/// Weight Planner). Fat and lean mass change in the Forbes proportion, and
/// maintenance falls or rises as they do, so the result is not the fixed
/// 3,500 kcal/lb rule. It omits adaptive thermogenesis, so it is a guide
/// and not the NIDDK tool.
List<ProjectionPoint> projectWeight({
  required EnergyProfile profile,
  required double maintenanceKcal,
  required double intakeKcal,
  required int days,
  int everyDays = 7,
}) {
  if (days < 1 || days > 1825) {
    throw const EnergyInputError('Projection length must be 1 to 1825 days.');
  }
  if (intakeKcal < 800 || intakeKcal > 8000) {
    throw const EnergyInputError('Intake must be between 800 and 8000 kcal.');
  }
  const double rhoFat = 9400;
  const double rhoLean = 1816;
  const double forbesC = 10.4 * rhoLean / rhoFat;
  const double kcalPerKgLean = 22;
  const double kcalPerKgFat = 3.2;

  final double bf0 = profile.bodyFatPercent ?? estimateBodyFatPercent(profile);
  final double fat0 = profile.weightKg * bf0 / 100;
  final double lean0 = profile.weightKg - fat0;
  double fat = fat0;
  double lean = lean0;

  final List<ProjectionPoint> out = <ProjectionPoint>[
    ProjectionPoint(0, fat + lean, maintenanceKcal)
  ];
  for (int d = 1; d <= days; d++) {
    final double expenditure = maintenanceKcal +
        kcalPerKgLean * (lean - lean0) +
        kcalPerKgFat * (fat - fat0);
    final double balance = intakeKcal - expenditure;
    final double p = forbesC / (forbesC + fat);
    lean += p * balance / rhoLean;
    fat = math.max(1, fat + (1 - p) * balance / rhoFat);
    if (d % everyDays == 0 || d == days) {
      out.add(ProjectionPoint(d, fat + lean, expenditure));
    }
  }
  return out;
}
