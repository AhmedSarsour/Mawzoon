import '../localization/localized_text.dart';
import 'portion_scale.dart';

/// What one Mawzoon plate is aiming at, per portion.
///
/// A **target**, never a cap. The distinction is the whole reason this class
/// exists separately from [BalanceBand]: the band describes where a plate's
/// energy sits, while this describes what the guest is trying to reach. A
/// plate that clears its protein target is doing the thing the restaurant
/// exists for; a plate that exceeds it has not failed at anything.
///
/// Nothing in the app compares a guest's plate to a daily requirement. A
/// single meal is not a diet, and an app that pretends otherwise starts
/// making claims it cannot support.
final class MacroTargets {
  /// Creates a target set.
  const MacroTargets({
    required this.proteinGrams,
    required this.fiberGrams,
  })  : assert(proteinGrams > 0, 'proteinGrams must be positive'),
        assert(fiberGrams > 0, 'fiberGrams must be positive');

  /// The house portion: 40 g of protein and 8 g of fibre on the plate.
  static const MacroTargets standard =
      MacroTargets(proteinGrams: 40, fiberGrams: 8);

  /// The loaded portion, scaled for someone eating around training.
  static const MacroTargets athletic =
      MacroTargets(proteinGrams: 60, fiberGrams: 10);

  /// The targets for [scale].
  static MacroTargets forScale(PortionScale scale) => switch (scale) {
        PortionScale.standardBalance => standard,
        PortionScale.athleticLoad => athletic,
      };

  /// Grams of protein a plate at this portion aims to carry.
  final double proteinGrams;

  /// Grams of dietary fibre a plate at this portion aims to carry.
  final double fiberGrams;

  /// Progress toward the protein target, clamped to `0.0..1.0`.
  ///
  /// Clamped so that a plate carrying more than the target renders a full bar
  /// rather than one that overshoots and reads as a penalty. The unclamped
  /// figure is available as [rawProteinProgress] when the difference matters.
  double proteinProgress(double grams) =>
      (grams / proteinGrams).clamp(0.0, 1.0);

  /// Progress toward the protein target, unclamped.
  double rawProteinProgress(double grams) => grams / proteinGrams;

  /// Whether [grams] reaches the protein target.
  bool meetsProtein(double grams) => grams >= proteinGrams;

  /// Progress toward the fibre target, clamped to `0.0..1.0`.
  double fiberProgress(double grams) => (grams / fiberGrams).clamp(0.0, 1.0);

  /// Whether [grams] reaches the fibre target.
  bool meetsFiber(double grams) => grams >= fiberGrams;

  /// How a plate's protein reads against the target.
  ///
  /// Both readings are written in the same register: one says the plate is
  /// still filling up, the other that it has arrived. Neither scolds.
  LocalizedText proteinCaption(double grams) => meetsProtein(grams)
      ? const LocalizedText(ar: 'بروتين وافٍ', en: 'Protein met')
      : const LocalizedText(ar: 'البروتين', en: 'Protein');

  @override
  String toString() =>
      'MacroTargets(P${proteinGrams.round()}g, fibre${fiberGrams.round()}g)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MacroTargets &&
          other.proteinGrams == proteinGrams &&
          other.fiberGrams == fiberGrams;

  @override
  int get hashCode => Object.hash(proteinGrams, fiberGrams);
}
