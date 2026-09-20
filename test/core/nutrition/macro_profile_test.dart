import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/nutrition/macro_profile.dart';

void main() {
  group('MacroProfile energy derivation', () {
    test('applies the modified Atwater system, discounting fibre to 2 kcal/g', () {
      const MacroProfile profile = MacroProfile(
        proteinGrams: 10,
        carbohydrateGrams: 20,
        fatGrams: 5,
        dietaryFiberGrams: 8,
      );

      // protein 40 + net carb (20-8)*4 = 48 + fibre 8*2 = 16 + fat 45.
      expect(profile.kilocalories, closeTo(149, 1e-9));
    });

    test('differs from the naive 4/4/9 shortcut by the fibre discount', () {
      const MacroProfile highFibre = MacroProfile(
        proteinGrams: 7,
        carbohydrateGrams: 36,
        fatGrams: 3,
        dietaryFiberGrams: 6.5,
      );

      const double naive = 7 * 4 + 36 * 4 + 3 * 9;
      expect(highFibre.kilocalories, lessThan(naive));
      expect(naive - highFibre.kilocalories, closeTo(6.5 * 2, 1e-9));
    });

    test('splits energy into protein, carbohydrate and fat components', () {
      const MacroProfile profile = MacroProfile(
        proteinGrams: 10,
        carbohydrateGrams: 20,
        fatGrams: 5,
        dietaryFiberGrams: 8,
      );

      expect(
        profile.proteinKilocalories +
            profile.carbohydrateKilocalories +
            profile.fatKilocalories,
        closeTo(profile.kilocalories, 1e-9),
      );
      expect(profile.carbohydrateKilocalories, closeTo(48 + 16, 1e-9));
    });

    test('net carbohydrate never goes negative', () {
      const MacroProfile allFibre = MacroProfile(
        proteinGrams: 0,
        carbohydrateGrams: 5,
        fatGrams: 0,
        dietaryFiberGrams: 5,
      );

      expect(allFibre.netCarbohydrateGrams, 0);
      expect(allFibre.kilocalories, closeTo(10, 1e-9));
    });

    test('zero is the additive identity and carries no energy', () {
      expect(MacroProfile.zero.kilocalories, 0);
      const MacroProfile p = MacroProfile(
        proteinGrams: 3,
        carbohydrateGrams: 4,
        fatGrams: 5,
        dietaryFiberGrams: 1,
      );
      expect(p + MacroProfile.zero, p);
    });
  });

  group('MacroProfile algebra', () {
    const MacroProfile a = MacroProfile(
      proteinGrams: 10,
      carbohydrateGrams: 20,
      fatGrams: 4,
      dietaryFiberGrams: 3,
      sodiumMilligrams: 100,
    );
    const MacroProfile b = MacroProfile(
      proteinGrams: 5,
      carbohydrateGrams: 10,
      fatGrams: 2,
      dietaryFiberGrams: 2,
      sodiumMilligrams: 50,
    );

    test('addition sums every field', () {
      final MacroProfile sum = a + b;
      expect(sum.proteinGrams, 15);
      expect(sum.carbohydrateGrams, 30);
      expect(sum.fatGrams, 6);
      expect(sum.dietaryFiberGrams, 5);
      expect(sum.sodiumMilligrams, 150);
    });

    test('addition is energy-additive', () {
      expect((a + b).kilocalories, closeTo(a.kilocalories + b.kilocalories, 1e-9));
    });

    test('scaling is linear in energy', () {
      expect((a * 1.6).kilocalories, closeTo(a.kilocalories * 1.6, 1e-9));
      expect((a * 0).kilocalories, 0);
    });

    test('scaling preserves the fibre-subset invariant', () {
      final MacroProfile scaled = a * 2.5;
      expect(scaled.dietaryFiberGrams, lessThanOrEqualTo(scaled.carbohydrateGrams));
    });

    test('sum folds an arbitrary list and returns zero for an empty one', () {
      expect(MacroProfile.sum(const <MacroProfile>[]), MacroProfile.zero);
      expect(MacroProfile.sum(<MacroProfile>[a, b]), a + b);
    });

    test('copyWith replaces only the named fields', () {
      final MacroProfile tweaked = a.copyWith(proteinGrams: 99);
      expect(tweaked.proteinGrams, 99);
      expect(tweaked.carbohydrateGrams, a.carbohydrateGrams);
      expect(tweaked.sodiumMilligrams, a.sodiumMilligrams);
    });

    test('value equality and hashing follow every field', () {
      expect(a, equals(a.copyWith()));
      expect(a.hashCode, a.copyWith().hashCode);
      expect(a, isNot(equals(b)));
    });
  });

  group('MacroProfile invariants', () {
    test('rejects a negative mass', () {
      expect(
        () => MacroProfile(
          proteinGrams: -1,
          carbohydrateGrams: 0,
          fatGrams: 0,
          dietaryFiberGrams: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects fibre exceeding total carbohydrate', () {
      expect(
        () => MacroProfile(
          proteinGrams: 0,
          carbohydrateGrams: 3,
          fatGrams: 0,
          dietaryFiberGrams: 4,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a negative portion factor', () {
      const MacroProfile p = MacroProfile(
        proteinGrams: 1,
        carbohydrateGrams: 1,
        fatGrams: 1,
        dietaryFiberGrams: 0,
      );
      expect(() => p * -1, throwsA(isA<AssertionError>()));
    });
  });
}
