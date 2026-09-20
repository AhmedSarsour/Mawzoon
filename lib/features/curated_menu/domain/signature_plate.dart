import '../../../core/localization/localized_text.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../plate_builder/domain/plate_selection.dart';

/// A chef-composed plate: the Curated Track's unit of one-tap ordering.
///
/// A signature plate is *not* a separate kind of food. It is a named
/// [PlateSelection] the kitchen has already balanced, which is why a guest can
/// open one in the Plate Architect and start swapping without leaving the
/// mental model behind. The tri-partition is preserved end to end.
final class SignaturePlate {
  /// Creates a signature plate.
  const SignaturePlate({
    required this.id,
    required this.name,
    required this.tagline,
    required this.chefNote,
    required this.protein,
    required this.carb,
    required this.fiber,
    required this.basePriceMinorUnits,
  })  : assert(id.length > 0, 'id must not be empty'),
        assert(basePriceMinorUnits > 0, 'basePriceMinorUnits must be positive');

  /// Stable identifier for deep links, re-orders and analytics.
  final String id;

  /// The plate's name on the menu board.
  final LocalizedText name;

  /// A six-word hook, read before the guest reads anything else.
  final LocalizedText tagline;

  /// Why the chef put these three things together. Sensory, never clinical.
  final LocalizedText chefNote;

  /// The protein compartment.
  final ProteinOption protein;

  /// The smart-carb compartment.
  final CarbOption carb;

  /// The vital-fibre compartment.
  final FiberOption fiber;

  /// Price of the plate before component surcharges, in minor units.
  final int basePriceMinorUnits;

  /// This plate as an editable selection at [scale].
  PlateSelection selectionAt(PortionScale scale) => PlateSelection(
        protein: protein,
        carb: carb,
        fiber: fiber,
        scale: scale,
      );

  /// Nutrition for this plate at [scale].
  NutritionalSummary summaryAt(PortionScale scale) =>
      selectionAt(scale).summary;

  /// Total price at [scale], including component surcharges.
  ///
  /// The Athletic Load carries a flat uplift rather than a per-gram one: the
  /// guest is buying a bigger plate, not auditing a scale ticket.
  int priceAt(PortionScale scale) {
    final int surcharges = protein.surchargeMinorUnits +
        carb.surchargeMinorUnits +
        fiber.surchargeMinorUnits;
    final int loadUplift = switch (scale) {
      PortionScale.standardBalance => 0,
      PortionScale.athleticLoad => _athleticLoadUpliftMinorUnits,
    };
    return basePriceMinorUnits + surcharges + loadUplift;
  }

  static const int _athleticLoadUpliftMinorUnits = 1500;

  @override
  String toString() => 'SignaturePlate($id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SignaturePlate && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
