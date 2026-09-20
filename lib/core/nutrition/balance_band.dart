import '../localization/localized_text.dart';
import 'portion_scale.dart';

/// How a plate's energy reads relative to the house nominal for its scale.
///
/// The three cases are deliberately symmetrical in tone. A lighter plate is
/// not "good" and a heartier plate is not "bad"; they are simply different
/// amounts of fuel. No case carries a warning, a cap, or an alarm colour.
enum PlateEnergyFraming {
  /// Meaningfully below the house nominal.
  lighter(
    headline: LocalizedText(ar: 'طبق خفيف', en: 'A lighter plate'),
    detail: LocalizedText(
      ar: 'وقود أقل من المعتاد — مناسب ليوم هادئ',
      en: 'Less fuel than usual — good for a quieter day',
    ),
  ),

  /// Sitting inside the house band.
  balanced(
    headline: LocalizedText(ar: 'موزون', en: 'Balanced'),
    detail: LocalizedText(
      ar: 'ضمن التوازن الذي صممه الشيف',
      en: "Right inside the chef's balance",
    ),
  ),

  /// Meaningfully above the house nominal.
  heartier(
    headline: LocalizedText(ar: 'طبق دسم', en: 'A heartier plate'),
    detail: LocalizedText(
      ar: 'وقود إضافي — مناسب بعد التمرين',
      en: 'Extra fuel — good after training',
    ),
  );

  const PlateEnergyFraming({required this.headline, required this.detail});

  /// Two or three words describing the plate.
  final LocalizedText headline;

  /// A supporting sentence framing the energy as purpose, not transgression.
  final LocalizedText detail;
}

/// The energy window a curated plate is designed to land in, per scale.
///
/// A band is a *design target for the kitchen*, used to validate the chef's
/// signature menu and to describe a custom plate in plain language. It is
/// never enforced against a guest's own build: the Plate Architect will
/// happily assemble a plate outside the band and simply say so.
final class BalanceBand {
  /// Creates a band around [nominalKilocalories].
  const BalanceBand({
    required this.nominalKilocalories,
    required this.toleranceKilocalories,
  })  : assert(nominalKilocalories > 0, 'nominal must be positive'),
        assert(toleranceKilocalories > 0, 'tolerance must be positive');

  /// The band for [PortionScale.standardBalance]: 550 ± 75 kcal.
  static const BalanceBand standard = BalanceBand(
    nominalKilocalories: 550,
    toleranceKilocalories: 75,
  );

  /// The band for [PortionScale.athleticLoad]: 780 ± 80 kcal.
  static const BalanceBand athletic = BalanceBand(
    nominalKilocalories: 780,
    toleranceKilocalories: 80,
  );

  /// The band matching [scale].
  static BalanceBand forScale(PortionScale scale) => switch (scale) {
        PortionScale.standardBalance => standard,
        PortionScale.athleticLoad => athletic,
      };

  /// The centre of the band.
  final int nominalKilocalories;

  /// Half-width of the band.
  final int toleranceKilocalories;

  /// Lowest energy still considered balanced.
  int get lowerBoundKilocalories =>
      nominalKilocalories - toleranceKilocalories;

  /// Highest energy still considered balanced.
  int get upperBoundKilocalories =>
      nominalKilocalories + toleranceKilocalories;

  /// Whether [kilocalories] falls inside the band, inclusive of both bounds.
  bool contains(double kilocalories) =>
      kilocalories >= lowerBoundKilocalories &&
      kilocalories <= upperBoundKilocalories;

  /// Describes where [kilocalories] sits relative to the band.
  PlateEnergyFraming classify(double kilocalories) {
    if (kilocalories < lowerBoundKilocalories) return PlateEnergyFraming.lighter;
    if (kilocalories > upperBoundKilocalories) return PlateEnergyFraming.heartier;
    return PlateEnergyFraming.balanced;
  }

  @override
  String toString() =>
      'BalanceBand($lowerBoundKilocalories–$upperBoundKilocalories kcal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BalanceBand &&
          other.nominalKilocalories == nominalKilocalories &&
          other.toleranceKilocalories == toleranceKilocalories;

  @override
  int get hashCode => Object.hash(nominalKilocalories, toleranceKilocalories);
}
