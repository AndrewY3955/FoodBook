import 'package:cookistrybook/src/data/energy_model.dart';
import 'package:cookistrybook/src/data/repositories/nutrition_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('body profile survives a json round trip', () {
    const BodyProfile p = BodyProfile(
      sex: Sex.female,
      ageYears: 34,
      heightCm: 168,
      weightKg: 70.5,
      activity: ActivityLevel.moderate,
      equation: BmrEquation.cunningham,
      bodyFatPercent: 27.5,
      bodyFatMeasured: true,
      weightUnit: WeightUnit.kg,
    );
    final BodyProfile back = BodyProfile.fromJson(p.toJson());
    expect(back.sex, Sex.female);
    expect(back.ageYears, 34);
    expect(back.heightCm, 168);
    expect(back.weightKg, 70.5);
    expect(back.activity, ActivityLevel.moderate);
    expect(back.equation, BmrEquation.cunningham);
    expect(back.bodyFatPercent, 27.5);
    expect(back.bodyFatMeasured, isTrue);
    expect(back.weightUnit, WeightUnit.kg);
  });

  test('a guessed body-fat value is never stored as measured', () {
    const BodyProfile p = BodyProfile(
      sex: Sex.male,
      ageYears: 40,
      heightCm: 180,
      weightKg: 85,
      bodyFatMeasured: true,
    );
    expect(p.toJson()['body_fat_measured'], isFalse);
  });

  test('out-of-range profiles are rejected with a readable message', () {
    const BodyProfile p =
        BodyProfile(sex: Sex.male, ageYears: 12, heightCm: 150, weightKg: 50);
    expect(p.toEnergyProfile, throwsA(isA<EnergyInputError>()));
  });
}
