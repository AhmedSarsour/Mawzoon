import 'dart:math' as math;

import '../localization/localized_text.dart';

/// How quickly a plate's carbohydrate is likely to reach the bloodstream.
///
/// Framed the same way energy is: three readings in one neutral register.
/// A quick-release plate is not a mistake — it is what an athlete eating
/// straight after training actually wants.
enum GlycemicBalance {
  /// Slow, level release. Whole grains and legumes territory.
  steady(
    headline: LocalizedText(ar: 'إطلاق بطيء', en: 'Steady release'),
    detail: LocalizedText(
      ar: 'طاقة تدوم طويلًا دون ارتفاع حاد',
      en: 'Long, level energy with no sharp climb',
    ),
  ),

  /// The middle band, where most balanced plates sit.
  balanced(
    headline: LocalizedText(ar: 'إطلاق متوازن', en: 'Balanced release'),
    detail: LocalizedText(
      ar: 'طاقة متدرّجة — الوضع المعتاد لطبق موزون',
      en: 'Gradual energy — where a Mawzoon plate usually lands',
    ),
  ),

  /// Fast release. Useful, and named as such.
  quick(
    headline: LocalizedText(ar: 'إطلاق سريع', en: 'Quick release'),
    detail: LocalizedText(
      ar: 'طاقة سريعة — مناسبة مباشرة بعد التمرين',
      en: 'Fast energy — what you want straight after training',
    ),
  );

  const GlycemicBalance({required this.headline, required this.detail});

  /// Two or three words describing the release.
  final LocalizedText headline;

  /// A supporting sentence framing the release as purpose, not transgression.
  final LocalizedText detail;
}

/// The glycemic reading for a whole plate.
///
/// [load] is glycemic load, the standard published metric: the glycemic index
/// of each component weighted by how much digestible carbohydrate it actually
/// contributes, summed across the plate. It is computed, not estimated.
///
/// [dampedLoad] applies a bounded reduction for the protein, fat and fibre
/// sharing the plate. That mixed meals raise blood glucose more slowly than
/// their carbohydrate alone is well established — protein and fat slow gastric
/// emptying, and fibre slows absorption — but the size of the effect varies
/// per person and per meal. So the adjustment here is **a deliberately coarse
/// directional heuristic for ordering a meal, not a clinical prediction**, it
/// is capped at [maxDampingFraction], and [load] is always kept alongside it
/// unmodified so nothing downstream has to trust the adjustment.
final class GlycemicProfile {
  const GlycemicProfile._({
    required this.load,
    required this.dampedLoad,
    required this.balance,
  });

  /// Computes the reading for a plate.
  ///
  /// [load] is supplied by the caller because glycemic load is per-component
  /// arithmetic — glycemic index against that component's own digestible
  /// carbohydrate — and cannot be recovered from plate totals.
  factory GlycemicProfile.fromPlate({
    required double load,
    required double proteinGrams,
    required double fatGrams,
    required double dietaryFiberGrams,
  }) {
    assert(load >= 0, 'glycemic load must be non-negative');

    final double damping = math.min(
      maxDampingFraction,
      proteinCoefficient * proteinGrams +
          fatCoefficient * fatGrams +
          fiberCoefficient * dietaryFiberGrams,
    );
    final double damped = load * (1 - damping);

    return GlycemicProfile._(
      load: load,
      dampedLoad: damped,
      // Banded on the published metric against published thresholds, not on
      // the damped figure. Banding the adjusted number would compound one
      // heuristic with another and let a plate of white rice argue its way
      // into the steady band on the strength of its side salad.
      balance: classify(load),
    );
  }

  /// A plate with no carbohydrate at all.
  static const GlycemicProfile zero = GlycemicProfile._(
    load: 0,
    dampedLoad: 0,
    balance: GlycemicBalance.steady,
  );

  /// Per gram of protein on the plate.
  static const double proteinCoefficient = 0.006;

  /// Per gram of fat on the plate.
  static const double fatCoefficient = 0.003;

  /// Per gram of dietary fibre on the plate. Weighted hardest of the three:
  /// fibre acts directly on absorption rather than on gastric emptying.
  static const double fiberCoefficient = 0.020;

  /// The damping is capped here so that no combination of sides can talk a
  /// plate of white rice into reading as a bowl of lentils.
  static const double maxDampingFraction = 0.35;

  /// Upper bound of [GlycemicBalance.steady].
  ///
  /// These are the conventional published meal-level glycemic-load bands —
  /// low at 10 or under, medium through 19, high at 20 and above — and not
  /// figures fitted to this menu. Fitting them to the menu would make the
  /// reading look informative while measuring nothing external: a threshold
  /// chosen so the plates spread evenly across three bands says only that
  /// three bands exist.
  ///
  /// On the current menu that places bulgur, pasta, quinoa and sweet potato
  /// plates in [GlycemicBalance.balanced] and basmati and potato plates in
  /// [GlycemicBalance.quick]. [GlycemicBalance.steady] needs a lower-carb
  /// plate than the menu currently offers, which is a fact about the menu
  /// worth being able to see rather than one to hide by moving the line.
  static const double steadyCeiling = 10;

  /// Upper bound of [GlycemicBalance.balanced].
  static const double balancedCeiling = 19;

  /// The band a glycemic load falls in.
  static GlycemicBalance classify(double glycemicLoad) {
    if (glycemicLoad <= steadyCeiling) return GlycemicBalance.steady;
    if (glycemicLoad <= balancedCeiling) return GlycemicBalance.balanced;
    return GlycemicBalance.quick;
  }

  /// The glycemic load of the plate as published: Σ (GI × net carb ÷ 100).
  final double load;

  /// [load] adjusted for the rest of the plate. See the class doc for what
  /// this figure is and is not.
  final double dampedLoad;

  /// The band [dampedLoad] falls in.
  final GlycemicBalance balance;

  /// How much the rest of the plate is judged to blunt the carbohydrate, in
  /// `0.0..maxDampingFraction`.
  double get dampingFraction => load <= 0 ? 0 : 1 - (dampedLoad / load);

  /// The published load, rounded for display. This is the figure a guest sees
  /// and the one [balance] is banded on.
  int get displayLoad => load.round();

  /// The damped load, rounded for display.
  int get displayDampedLoad => dampedLoad.round();

  @override
  String toString() => 'GlycemicProfile(load: ${load.toStringAsFixed(1)}, '
      'damped: ${dampedLoad.toStringAsFixed(1)}, ${balance.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlycemicProfile &&
          other.load == load &&
          other.dampedLoad == dampedLoad;

  @override
  int get hashCode => Object.hash(load, dampedLoad);
}
