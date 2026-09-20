import '../localization/localized_text.dart';
import '../menu/plate_segment.dart';

/// The binary volume toggle that sits on every plate, curated or custom.
///
/// Two options, never a slider. A hungry guest suffering ego depletion can
/// resolve a binary choice in well under a second; a continuous control forces
/// them to invent a preference they do not have.
///
/// The scale is deliberately *non-uniform* across compartments. Loading an
/// athlete's plate means more protein and more fuel, not a proportionally
/// larger pile of leaves — the greens compartment grows only slightly, which
/// is how a kitchen actually plates a larger portion.
enum PortionScale {
  /// The house portion. Nominally ~550 kcal on a curated signature plate.
  standardBalance(
    label: LocalizedText(ar: 'التوازن القياسي', en: 'Standard Balance'),
    nominalKilocalories: 550,
    proteinFactor: 1.0,
    carbFactor: 1.0,
    fiberFactor: 1.0,
  ),

  /// The loaded portion. Nominally ~780 kcal on a curated signature plate.
  athleticLoad(
    label: LocalizedText(ar: 'الحِمل الرياضي', en: 'Athletic Load'),
    nominalKilocalories: 780,
    proteinFactor: 1.6,
    carbFactor: 1.5,
    fiberFactor: 1.15,
  );

  const PortionScale({
    required this.label,
    required this.nominalKilocalories,
    required double proteinFactor,
    required double carbFactor,
    required double fiberFactor,
  })  : _proteinFactor = proteinFactor,
        _carbFactor = carbFactor,
        _fiberFactor = fiberFactor;

  /// The toggle's display name.
  final LocalizedText label;

  /// The energy a curated signature plate targets at this scale.
  ///
  /// This is a design target for the chef's menu, not a cap imposed on the
  /// guest. A custom plate is free to land anywhere; it is simply *described*
  /// relative to this figure.
  final int nominalKilocalories;

  final double _proteinFactor;
  final double _carbFactor;
  final double _fiberFactor;

  /// The mass multiplier applied to a component in [segment] at this scale.
  double factorFor(PlateSegment segment) => switch (segment) {
        PlateSegment.protein => _proteinFactor,
        PlateSegment.smartCarb => _carbFactor,
        PlateSegment.vitalFiber => _fiberFactor,
      };

  /// The other scale — what the toggle flips to.
  PortionScale get toggled => switch (this) {
        PortionScale.standardBalance => PortionScale.athleticLoad,
        PortionScale.athleticLoad => PortionScale.standardBalance,
      };
}
