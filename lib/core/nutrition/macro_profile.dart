import 'dart:math' as math;

/// Atwater energy conversion factors, in kilocalories per gram.
///
/// Mawzoon uses the *modified* Atwater system rather than the coarse
/// 4/4/9 shortcut: dietary fibre is only partially metabolised, so it is
/// billed at 2 kcal/g and subtracted out of the carbohydrate pool before the
/// carbohydrate factor is applied. A plate of freekeh and broccolini differs
/// from the naive calculation by 25–30 kcal, which is exactly the margin a
/// guest tracking macros would notice.
abstract final class AtwaterFactors {
  /// Protein, 4 kcal per gram.
  static const double proteinKcalPerGram = 4.0;

  /// Carbohydrate excluding dietary fibre, 4 kcal per gram.
  static const double netCarbohydrateKcalPerGram = 4.0;

  /// Dietary fibre, 2 kcal per gram (partially fermented, partially excreted).
  static const double dietaryFiberKcalPerGram = 2.0;

  /// Fat, 9 kcal per gram.
  static const double fatKcalPerGram = 9.0;
}

/// The measured macronutrient content of a food component or a whole plate.
///
/// All masses are in grams except [sodiumMilligrams]. [carbohydrateGrams] is
/// *total* carbohydrate and therefore includes [dietaryFiberGrams], mirroring
/// how nutrition panels are published; [netCarbohydrateGrams] derives the
/// digestible remainder.
///
/// Energy is never stored. It is always derived from mass via
/// [AtwaterFactors], so a profile cannot drift out of sync with its own
/// calorie count — there is exactly one source of truth.
final class MacroProfile {
  /// Creates a macronutrient profile. All masses must be non-negative and
  /// fibre can never exceed the total carbohydrate it is a subset of.
  const MacroProfile({
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    required this.dietaryFiberGrams,
    this.sodiumMilligrams = 0,
  })  : assert(proteinGrams >= 0, 'proteinGrams must be non-negative'),
        assert(carbohydrateGrams >= 0, 'carbohydrateGrams must be non-negative'),
        assert(fatGrams >= 0, 'fatGrams must be non-negative'),
        assert(dietaryFiberGrams >= 0, 'dietaryFiberGrams must be non-negative'),
        assert(sodiumMilligrams >= 0, 'sodiumMilligrams must be non-negative'),
        assert(
          dietaryFiberGrams <= carbohydrateGrams,
          'dietaryFiberGrams is a subset of carbohydrateGrams and cannot exceed it',
        );

  /// A profile with no mass in any macronutrient — the additive identity.
  static const MacroProfile zero = MacroProfile(
    proteinGrams: 0,
    carbohydrateGrams: 0,
    fatGrams: 0,
    dietaryFiberGrams: 0,
  );

  /// Grams of protein.
  final double proteinGrams;

  /// Grams of total carbohydrate, inclusive of [dietaryFiberGrams].
  final double carbohydrateGrams;

  /// Grams of fat.
  final double fatGrams;

  /// Grams of dietary fibre.
  final double dietaryFiberGrams;

  /// Milligrams of sodium.
  final double sodiumMilligrams;

  /// Digestible carbohydrate: total carbohydrate less dietary fibre.
  double get netCarbohydrateGrams =>
      math.max(0, carbohydrateGrams - dietaryFiberGrams);

  /// Total metabolisable energy in kilocalories, derived via [AtwaterFactors].
  double get kilocalories =>
      proteinGrams * AtwaterFactors.proteinKcalPerGram +
      netCarbohydrateGrams * AtwaterFactors.netCarbohydrateKcalPerGram +
      dietaryFiberGrams * AtwaterFactors.dietaryFiberKcalPerGram +
      fatGrams * AtwaterFactors.fatKcalPerGram;

  /// Energy contributed by protein alone, in kilocalories.
  double get proteinKilocalories =>
      proteinGrams * AtwaterFactors.proteinKcalPerGram;

  /// Energy contributed by all carbohydrate, fibre included, in kilocalories.
  double get carbohydrateKilocalories =>
      netCarbohydrateGrams * AtwaterFactors.netCarbohydrateKcalPerGram +
      dietaryFiberGrams * AtwaterFactors.dietaryFiberKcalPerGram;

  /// Energy contributed by fat alone, in kilocalories.
  double get fatKilocalories => fatGrams * AtwaterFactors.fatKcalPerGram;

  /// Combines two profiles by summing every field.
  MacroProfile operator +(MacroProfile other) => MacroProfile(
        proteinGrams: proteinGrams + other.proteinGrams,
        carbohydrateGrams: carbohydrateGrams + other.carbohydrateGrams,
        fatGrams: fatGrams + other.fatGrams,
        dietaryFiberGrams: dietaryFiberGrams + other.dietaryFiberGrams,
        sodiumMilligrams: sodiumMilligrams + other.sodiumMilligrams,
      );

  /// Scales every field by [factor], which must be non-negative.
  ///
  /// Scaling the whole profile uniformly preserves the fibre-subset invariant,
  /// so a scaled profile is always constructible.
  MacroProfile operator *(double factor) {
    assert(factor >= 0, 'Portion factors must be non-negative, got $factor');
    return MacroProfile(
      proteinGrams: proteinGrams * factor,
      carbohydrateGrams: carbohydrateGrams * factor,
      fatGrams: fatGrams * factor,
      dietaryFiberGrams: dietaryFiberGrams * factor,
      sodiumMilligrams: sodiumMilligrams * factor,
    );
  }

  /// Sums an arbitrary number of profiles, returning [zero] for an empty list.
  static MacroProfile sum(Iterable<MacroProfile> profiles) =>
      profiles.fold(zero, (MacroProfile acc, MacroProfile p) => acc + p);

  /// Returns a copy with the provided fields replaced.
  MacroProfile copyWith({
    double? proteinGrams,
    double? carbohydrateGrams,
    double? fatGrams,
    double? dietaryFiberGrams,
    double? sodiumMilligrams,
  }) =>
      MacroProfile(
        proteinGrams: proteinGrams ?? this.proteinGrams,
        carbohydrateGrams: carbohydrateGrams ?? this.carbohydrateGrams,
        fatGrams: fatGrams ?? this.fatGrams,
        dietaryFiberGrams: dietaryFiberGrams ?? this.dietaryFiberGrams,
        sodiumMilligrams: sodiumMilligrams ?? this.sodiumMilligrams,
      );

  @override
  String toString() => 'MacroProfile('
      'P: ${proteinGrams.toStringAsFixed(1)}g, '
      'C: ${carbohydrateGrams.toStringAsFixed(1)}g '
      '(fibre ${dietaryFiberGrams.toStringAsFixed(1)}g), '
      'F: ${fatGrams.toStringAsFixed(1)}g, '
      '${kilocalories.round()} kcal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MacroProfile &&
          other.proteinGrams == proteinGrams &&
          other.carbohydrateGrams == carbohydrateGrams &&
          other.fatGrams == fatGrams &&
          other.dietaryFiberGrams == dietaryFiberGrams &&
          other.sodiumMilligrams == sodiumMilligrams;

  @override
  int get hashCode => Object.hash(
        proteinGrams,
        carbohydrateGrams,
        fatGrams,
        dietaryFiberGrams,
        sodiumMilligrams,
      );
}
