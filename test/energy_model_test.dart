import 'dart:math' as math;

import 'package:cookistrybook/src/data/energy_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Reference values below were computed independently in Python from the
// published equations, not from this code.
EnergyProfile male({
  double w = 80,
  double age = 30,
  ActivityLevel a = ActivityLevel.sedentary,
  BmrEquation eq = BmrEquation.mifflinStJeor,
  double? bf,
}) =>
    EnergyProfile(
        sex: Sex.male,
        ageYears: age,
        weightKg: w,
        heightCm: 180,
        activity: a,
        equation: eq,
        bodyFatPercent: bf);

final DateTime t0 = DateTime.utc(2026, 1, 1);

/// Simulates [days] days. Weight follows (intake - trueTdee) / 7700 with
/// deterministic day-to-day water noise of about +/-0.4 kg.
({List<DailyIntake> intake, List<WeighIn> weights}) simulate({
  required double trueTdee,
  required double intakeKcal,
  int days = 28,
  double startKg = 80,
  bool Function(int day)? logIntake,
  bool Function(int day)? weigh,
  double Function(int day)? spike,
  double noise = 0.4,
}) {
  final List<DailyIntake> i = <DailyIntake>[];
  final List<WeighIn> w = <WeighIn>[];
  double kg = startKg;
  for (int d = 0; d < days; d++) {
    final DateTime day = t0.add(Duration(days: d));
    final double n = noise * math.sin(d * 2.399);
    if (logIntake?.call(d) ?? true) i.add(DailyIntake(day, intakeKcal));
    if (weigh?.call(d) ?? true) {
      w.add(WeighIn(day, kg + n + (spike?.call(d) ?? 0)));
    }
    kg += (intakeKcal - trueTdee) / 7700;
  }
  return (intake: i, weights: w);
}

DateTime endOf(int days) => t0.add(Duration(days: days - 1));

void main() {
  group('BMR equations', () {
    test('Mifflin-St Jeor male and female', () {
      expect(computeBmr(male()).kcal, closeTo(1780.0, 1e-9));
      final EnergyProfile f = EnergyProfile(
          sex: Sex.female, ageYears: 30, weightKg: 65, heightCm: 165);
      expect(computeBmr(f).kcal, closeTo(1370.25, 1e-9));
    });

    test('reported example uses a conservative light-activity estimate', () {
      final double kg = weightToKg(190, WeightUnit.lb);
      final double cm = heightToCm(HeightUnit.feetInches, 5, inches: 6);
      final EnergyProfile p = EnergyProfile(
        sex: Sex.male,
        ageYears: 20,
        weightKg: kg,
        heightCm: cm,
        activity: ActivityLevel.light,
      );
      expect(computeBmr(p).kcal, closeTo(1814.58, 0.01));
      expect(formulaTdee(p).tdee, closeTo(2268.22, 0.02));
      expect(formulaTdee(p.copyWith(activity: ActivityLevel.sedentary)).tdee,
          closeTo(2177.49, 0.02));
    });

    test('Revised Harris-Benedict', () {
      expect(computeBmr(male(eq: BmrEquation.revisedHarrisBenedict)).kcal,
          closeTo(1853.632, 1e-9));
      final EnergyProfile f = EnergyProfile(
          sex: Sex.female,
          ageYears: 30,
          weightKg: 65,
          heightCm: 165,
          equation: BmrEquation.revisedHarrisBenedict);
      expect(computeBmr(f).kcal, closeTo(1429.918, 1e-9));
    });

    test('Cunningham uses fat-free mass', () {
      expect(computeBmr(male(eq: BmrEquation.cunningham, bf: 20)).kcal,
          closeTo(1908, 1e-9));
    });

    test('ten Haaf weight-based', () {
      expect(computeBmr(male(eq: BmrEquation.tenHaaf)).kcal,
          closeTo(1989.2264, 1e-6));
      final EnergyProfile f = EnergyProfile(
          sex: Sex.female,
          ageYears: 30,
          weightKg: 65,
          heightCm: 165,
          equation: BmrEquation.tenHaaf);
      expect(computeBmr(f).kcal, closeTo(1531.0002, 1e-6));
    });

    test('equations are reported, never averaged', () {
      expect(computeBmr(male()).equation, BmrEquation.mifflinStJeor);
      expect(computeBmr(male(eq: BmrEquation.tenHaaf)).equation,
          BmrEquation.tenHaaf);
    });

    test('measured vs estimated body fat is distinguished', () {
      final EnergyProfile guess = EnergyProfile(
          sex: Sex.male,
          ageYears: 30,
          weightKg: 80,
          heightCm: 180,
          equation: BmrEquation.cunningham,
          bodyFatPercent: 20);
      expect(computeBmr(guess).notes.join(), contains('your own estimate'));
      final EnergyProfile measured = EnergyProfile(
          sex: Sex.male,
          ageYears: 30,
          weightKg: 80,
          heightCm: 180,
          equation: BmrEquation.cunningham,
          bodyFatPercent: 20,
          bodyFatMeasured: true);
      expect(computeBmr(measured).notes, isEmpty);
    });
  });

  group('units', () {
    test('pounds, inches and feet/inches convert exactly', () {
      expect(weightToKg(180, WeightUnit.lb), closeTo(81.6466266, 1e-9));
      expect(weightToKg(80, WeightUnit.kg), 80);
      expect(heightToCm(HeightUnit.cm, 177.8), 177.8);
      expect(heightToCm(HeightUnit.inch, 70), closeTo(177.8, 1e-9));
      expect(heightToCm(HeightUnit.feetInches, 5, inches: 10),
          closeTo(177.8, 1e-9));
    });

    test('lb input reaches the same BMR as the kg equivalent', () {
      final double kg = weightToKg(180, WeightUnit.lb);
      final double cm = heightToCm(HeightUnit.feetInches, 5, inches: 10);
      final double bmr = computeBmr(EnergyProfile(
              sex: Sex.male, ageYears: 30, weightKg: kg, heightCm: cm))
          .kcal;
      expect(bmr, closeTo(10 * 81.6466266 + 6.25 * 177.8 - 150 + 5, 1e-6));
    });

    test('rejects bad units input', () {
      expect(() => heightToCm(HeightUnit.feetInches, 5, inches: 12),
          throwsA(isA<EnergyInputError>()));
      expect(() => heightToCm(HeightUnit.feetInches, 5, inches: -1),
          throwsA(isA<EnergyInputError>()));
      expect(() => weightToKg(double.nan, WeightUnit.kg),
          throwsA(isA<EnergyInputError>()));
    });
  });

  group('activity', () {
    test('every multiplier', () {
      const List<double> expected = <double>[
        2136.0,
        2225.0,
        2581.0,
        2848.0,
        3115.0,
      ];
      for (int i = 0; i < ActivityLevel.values.length; i++) {
        final ActivityLevel a = ActivityLevel.values[i];
        expect(formulaTdee(male(a: a)).tdee, closeTo(expected[i], 1e-9),
            reason: a.label);
      }
      expect(ActivityLevel.values.map((ActivityLevel a) => a.factor),
          <double>[1.2, 1.25, 1.45, 1.6, 1.75]);
    });

    test('every level has an explanation', () {
      for (final ActivityLevel a in ActivityLevel.values) {
        expect(a.description.length, greaterThan(30));
      }
      expect(ActivityLevel.light.description, contains('1-3 gym days/week'));
      expect(ActivityLevel.moderate.description,
          contains('around 4 gym days/week'));
      expect(ActivityLevel.very.description, contains('10,000+ steps/day'));
      expect(ActivityLevel.very.description, contains('5-7 days/week'));
    });

    test('suggestion is conservative and does not double count', () {
      expect(
          suggestActivity(
              occupation: Occupation.seated,
              dailySteps: 3000,
              workoutsPerWeek: 0),
          ActivityLevel.sedentary);
      // Desk job but 3x/week workouts and ~6k steps is light, not moderate.
      expect(
          suggestActivity(
              occupation: Occupation.seated,
              dailySteps: 6000,
              workoutsPerWeek: 3),
          ActivityLevel.light);
      expect(
          suggestActivity(
              occupation: Occupation.onFeet,
              dailySteps: 9000,
              workoutsPerWeek: 4),
          ActivityLevel.moderate);
      expect(
          suggestActivity(
              occupation: Occupation.heavy,
              dailySteps: 13000,
              workoutsPerWeek: 6),
          ActivityLevel.extreme);
      expect(
          () => suggestActivity(
              occupation: Occupation.seated,
              dailySteps: -1,
              workoutsPerWeek: 0),
          throwsA(isA<EnergyInputError>()));
    });

    test('changing activity changes TDEE; BMR is unchanged', () {
      final FormulaEstimate a = formulaTdee(male());
      final FormulaEstimate b = formulaTdee(male(a: ActivityLevel.very));
      expect(b.bmr.kcal, a.bmr.kcal);
      expect(b.tdee, greaterThan(a.tdee));
    });
  });

  group('validation', () {
    test('rejects invalid measurements', () {
      EnergyProfile make({
        double age = 30,
        double w = 80,
        double h = 180,
        double? bf,
        BmrEquation eq = BmrEquation.mifflinStJeor,
      }) =>
          EnergyProfile(
              sex: Sex.male,
              ageYears: age,
              weightKg: w,
              heightCm: h,
              bodyFatPercent: bf,
              equation: eq);
      expect(() => make(age: 12), throwsA(isA<EnergyInputError>()));
      expect(() => make(age: 130), throwsA(isA<EnergyInputError>()));
      expect(() => make(w: 0), throwsA(isA<EnergyInputError>()));
      expect(() => make(w: -5), throwsA(isA<EnergyInputError>()));
      expect(() => make(w: 900), throwsA(isA<EnergyInputError>()));
      expect(() => make(h: 50), throwsA(isA<EnergyInputError>()));
      expect(() => make(h: double.nan), throwsA(isA<EnergyInputError>()));
      expect(() => make(bf: 1), throwsA(isA<EnergyInputError>()));
      expect(() => make(bf: 80), throwsA(isA<EnergyInputError>()));
    });

    test('Cunningham without body fat is rejected, not guessed', () {
      expect(() => male(eq: BmrEquation.cunningham),
          throwsA(isA<EnergyInputError>()));
    });

    test('results are not clamped or rounded internally', () {
      final double v =
          formulaTdee(male(w: 81.234, a: ActivityLevel.light)).tdee;
      expect(v, closeTo((10 * 81.234 + 6.25 * 180 - 150 + 5) * 1.25, 1e-9));
      expect(v, isNot(v.roundToDouble()));
      expect(roundKcal(2447.5), 2450);
      expect(roundKcal(2447.5, step: 10), 2450);
    });
  });

  group('calibration', () {
    test('weight loss: recovers true maintenance', () {
      final s = simulate(trueTdee: 2600, intakeKcal: 2100);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.usable, isTrue);
      expect(c.slopeKgPerDay!, lessThan(0));
      expect(c.empiricalTdee!, closeTo(2600, 150));
    });

    test('weight gain: recovers true maintenance', () {
      final s = simulate(trueTdee: 2400, intakeKcal: 2900);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.slopeKgPerDay!, greaterThan(0));
      expect(c.empiricalTdee!, closeTo(2400, 150));
    });

    test('stable weight: maintenance equals intake', () {
      final s = simulate(trueTdee: 2500, intakeKcal: 2500);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.empiricalTdee!, closeTo(2500, 120));
    });

    test('missing calorie logs are skipped, not counted as zero', () {
      final s = simulate(
          trueTdee: 2600, intakeKcal: 2100, logIntake: (int d) => d % 3 != 0);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.averageIntake!, closeTo(2100, 1e-9));
      expect(c.empiricalTdee!, closeTo(2600, 150));
      expect(c.intakeDays, lessThan(28));
    });

    test('zero or near-empty log days are ignored as incomplete', () {
      final s = simulate(trueTdee: 2600, intakeKcal: 2100);
      final List<DailyIntake> withZeros = <DailyIntake>[
        ...s.intake.where((DailyIntake x) => x.day.day != 5 && x.day.day != 6),
        DailyIntake(t0.add(const Duration(days: 4)), 0),
        DailyIntake(t0.add(const Duration(days: 5)), 150),
      ];
      final CalibrationResult c = calibrate(withZeros, s.weights, endOf(28));
      expect(c.averageIntake!, closeTo(2100, 1e-9));
    });

    test('missing weigh-ins: three a week still calibrates', () {
      final s = simulate(
          trueTdee: 2600,
          intakeKcal: 2100,
          weigh: (int d) => d % 7 == 0 || d % 7 == 2 || d % 7 == 4);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.usable, isTrue);
      expect(c.empiricalTdee!, closeTo(2600, 220));
    });

    test('too few weigh-ins is flagged unreliable', () {
      final s = simulate(
          trueTdee: 2600, intakeKcal: 2100, weigh: (int d) => d % 9 == 0);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.confidence, Confidence.insufficient);
      expect(c.empiricalTdee, isNull);
      expect(c.reasons.join(), contains('weigh-ins'));
    });

    test('a sudden water-weight spike does not move the result much', () {
      final clean = simulate(trueTdee: 2600, intakeKcal: 2100, noise: 0.1);
      final spiky = simulate(
          trueTdee: 2600,
          intakeKcal: 2100,
          noise: 0.1,
          spike: (int d) => d == 26 ? 3.0 : (d == 10 ? -2.0 : 0));
      final double a =
          calibrate(clean.intake, clean.weights, endOf(28)).empiricalTdee!;
      final double b =
          calibrate(spiky.intake, spiky.weights, endOf(28)).empiricalTdee!;
      expect((a - b).abs(), lessThan(120));
    });

    test('insufficient history: no empirical value, formula is kept', () {
      final s = simulate(trueTdee: 2600, intakeKcal: 2100, days: 14);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(14));
      expect(c.confidence, Confidence.insufficient);
      expect(c.blend, 0);
      final MaintenanceEstimate e = estimateMaintenance(
          male(a: ActivityLevel.moderate), s.intake, s.weights, endOf(14));
      expect(e.usedEmpirical, isFalse);
      expect(e.recommended, closeTo(e.formula.tdee, 1e-9));
    });

    test('sparse logging (under 60% of days) is insufficient', () {
      final s = simulate(
          trueTdee: 2600, intakeKcal: 2100, logIntake: (int d) => d % 3 == 0);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(28));
      expect(c.confidence, Confidence.insufficient);
      expect(c.reasons.join(), contains('% of days'));
    });

    test('no data at all', () {
      final CalibrationResult c =
          calibrate(<DailyIntake>[], <WeighIn>[], endOf(28));
      expect(c.confidence, Confidence.insufficient);
      expect(c.usable, isFalse);
    });

    test('28 clean days is high confidence; 21 days is not', () {
      final s28 = simulate(trueTdee: 2600, intakeKcal: 2100, noise: 0.1);
      expect(calibrate(s28.intake, s28.weights, endOf(28)).confidence,
          Confidence.high);
      final s21 = simulate(trueTdee: 2600, intakeKcal: 2100, days: 21);
      final Confidence c21 =
          calibrate(s21.intake, s21.weights, endOf(21)).confidence;
      expect(c21, anyOf(Confidence.low, Confidence.moderate));
    });

    test('uses only the latest 28 days', () {
      final s = simulate(trueTdee: 2600, intakeKcal: 2100, days: 60);
      final CalibrationResult c = calibrate(s.intake, s.weights, endOf(60));
      expect(c.trackedDays, lessThanOrEqualTo(28));
    });
  });

  group('recommendation', () {
    test('formula is preserved and recommendation moves toward data', () {
      // Person who truly burns about 2400 but the formula says ~2581.
      final s = simulate(trueTdee: 2400, intakeKcal: 2400, noise: 0.1);
      final EnergyProfile p = male(a: ActivityLevel.moderate);
      final MaintenanceEstimate e =
          estimateMaintenance(p, s.intake, s.weights, endOf(28));
      expect(
          e.formula.tdee,
          closeTo(formulaTdee(p.copyWith(weightKg: e.profile.weightKg)).tdee,
              1e-9));
      expect(e.usedEmpirical, isTrue);
      expect(e.recommended, lessThan(e.formula.tdee));
      expect(e.recommended, greaterThan(e.calibration.empiricalTdee!));
    });

    test('implausible data is capped and flagged', () {
      // Logged 900 kcal with no weight change would imply TDEE of 900.
      final s = simulate(trueTdee: 900, intakeKcal: 900, noise: 0.05);
      final EnergyProfile p = male(a: ActivityLevel.moderate);
      final MaintenanceEstimate e =
          estimateMaintenance(p, s.intake, s.weights, endOf(28));
      expect(e.flags, isNotEmpty);
      expect(e.recommended, greaterThan(e.formula.tdee * 0.5));
    });

    test('step limit prevents sudden jumps', () {
      final s = simulate(trueTdee: 2000, intakeKcal: 2000, noise: 0.05);
      final EnergyProfile p = male(a: ActivityLevel.moderate);
      final MaintenanceEstimate e = estimateMaintenance(
          p, s.intake, s.weights, endOf(28),
          previousRecommended: 2581);
      expect((e.recommended - 2581).abs(), lessThanOrEqualTo(100.0001));
    });

    test('formula tracks a change in body weight', () {
      final s =
          simulate(trueTdee: 2600, intakeKcal: 2100, noise: 0, startKg: 80);
      final MaintenanceEstimate e =
          estimateMaintenance(male(w: 80), s.intake, s.weights, endOf(28));
      expect(e.profile.weightKg, lessThan(80));
      expect(e.formula.tdee, lessThan(formulaTdee(male(w: 80)).tdee));
    });

    test('history is gradual and chronological', () {
      final s =
          simulate(trueTdee: 2300, intakeKcal: 2300, days: 63, noise: 0.1);
      final List<HistoryPoint> h = maintenanceHistory(
          male(a: ActivityLevel.moderate), s.intake, s.weights, endOf(63));
      expect(h.length, 8);
      for (int i = 1; i < h.length; i++) {
        expect(h[i].day.isAfter(h[i - 1].day), isTrue);
        expect(
            (h[i].estimate.recommended - h[i - 1].estimate.recommended).abs(),
            lessThanOrEqualTo(100.0001));
      }
      // Early points have no calibration; the last one does.
      expect(h.first.estimate.calibration.usable, isFalse);
      expect(h.last.estimate.calibration.usable, isTrue);
    });

    test('method text never claims a measured rate', () {
      final s = simulate(trueTdee: 2600, intakeKcal: 2100);
      final MaintenanceEstimate e =
          estimateMaintenance(male(), s.intake, s.weights, endOf(28));
      expect(e.method.toLowerCase(), isNot(contains('measured')));
    });
  });

  group('dynamic projection', () {
    test('a steady deficit loses weight, and the rate slows', () {
      final List<ProjectionPoint> p = projectWeight(
          profile: male(w: 90),
          maintenanceKcal: 2800,
          intakeKcal: 2300,
          days: 364);
      expect(p.last.weightKg, lessThan(90));
      final double firstMonth = p[0].weightKg - p[4].weightKg;
      final double lastMonth = p[p.length - 5].weightKg - p.last.weightKg;
      expect(lastMonth, lessThan(firstMonth));
      expect(p.last.maintenanceKcal, lessThan(2800));
    });

    test('eating at maintenance holds weight', () {
      final List<ProjectionPoint> p = projectWeight(
          profile: male(), maintenanceKcal: 2600, intakeKcal: 2600, days: 90);
      expect(p.last.weightKg, closeTo(80, 0.01));
    });

    test('a surplus gains weight; bad inputs are rejected', () {
      final List<ProjectionPoint> p = projectWeight(
          profile: male(), maintenanceKcal: 2600, intakeKcal: 3100, days: 90);
      expect(p.last.weightKg, greaterThan(80));
      expect(
          () => projectWeight(
              profile: male(),
              maintenanceKcal: 2600,
              intakeKcal: 100,
              days: 30),
          throwsA(isA<EnergyInputError>()));
    });

    test('Deurenberg body-fat estimate matches the reference', () {
      expect(estimateBodyFatPercent(male()), closeTo(20.3296296, 1e-5));
    });
  });
}
