import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';

/// The guest's raw choices: up to one component per compartment, plus the
/// volume toggle.
///
/// This is the *input* to the nutrition engine. Everything a screen displays —
/// calories, macro arcs, allergen chips, the balance verdict — is derived from
/// a [PlateSelection], never stored alongside it.
///
/// Immutable: every mutation returns a new instance, which makes the whole
/// builder trivially undoable and safe to diff between animation frames.
final class PlateSelection {
  /// Creates a selection. Any compartment may be empty.
  const PlateSelection({
    this.protein,
    this.carb,
    this.fiber,
    this.scale = PortionScale.standardBalance,
  });

  /// An untouched plate at the house portion.
  static const PlateSelection empty = PlateSelection();

  /// The chosen protein, if any.
  final ProteinOption? protein;

  /// The chosen smart carb, if any.
  final CarbOption? carb;

  /// The chosen vital fibre, if any.
  final FiberOption? fiber;

  /// The volume toggle.
  final PortionScale scale;

  /// Whether nothing at all has been chosen.
  bool get isEmpty => protein == null && carb == null && fiber == null;

  /// Whether all three compartments are filled.
  bool get isComplete => protein != null && carb != null && fiber != null;

  /// Compartments currently holding a component.
  Set<PlateSegment> get filledSegments => <PlateSegment>{
        if (protein != null) PlateSegment.protein,
        if (carb != null) PlateSegment.smartCarb,
        if (fiber != null) PlateSegment.vitalFiber,
      };

  /// The next compartment to fill in canonical order, or `null` when complete.
  PlateSegment? get nextSegment {
    for (final PlateSegment segment in PlateSegment.buildOrder) {
      if (optionFor(segment) == null) return segment;
    }
    return null;
  }

  /// The component chosen for [segment], or `null`.
  IngredientOption? optionFor(PlateSegment segment) => switch (segment) {
        PlateSegment.protein => protein,
        PlateSegment.smartCarb => carb,
        PlateSegment.vitalFiber => fiber,
      };

  /// The chosen components resolved to concrete portions at [scale].
  List<PortionedComponent> get portionedComponents => <PortionedComponent>[
        if (protein != null) protein!.atScale(scale),
        if (carb != null) carb!.atScale(scale),
        if (fiber != null) fiber!.atScale(scale),
      ];

  /// The derived nutritional picture of this selection.
  NutritionalSummary get summary => NutritionalSummary.fromComponents(
        scale: scale,
        components: portionedComponents,
      );

  /// Total component surcharge in minor currency units.
  int get surchargeMinorUnits =>
      (protein?.surchargeMinorUnits ?? 0) +
      (carb?.surchargeMinorUnits ?? 0) +
      (fiber?.surchargeMinorUnits ?? 0);

  /// Places [option] into its own compartment, replacing whatever was there.
  ///
  /// The compartment is inferred from the option's own type, so a caller can
  /// never file a salad under "protein".
  PlateSelection select(IngredientOption option) => switch (option) {
        final ProteinOption p => copyWith(protein: p),
        final CarbOption c => copyWith(carb: c),
        final FiberOption f => copyWith(fiber: f),
      };

  /// Empties [segment].
  PlateSelection clear(PlateSegment segment) => switch (segment) {
        PlateSegment.protein => PlateSelection(
            carb: carb,
            fiber: fiber,
            scale: scale,
          ),
        PlateSegment.smartCarb => PlateSelection(
            protein: protein,
            fiber: fiber,
            scale: scale,
          ),
        PlateSegment.vitalFiber => PlateSelection(
            protein: protein,
            carb: carb,
            scale: scale,
          ),
      };

  /// Flips the volume toggle, keeping every component.
  PlateSelection toggleScale() => copyWith(scale: scale.toggled);

  /// Returns a copy with the provided fields replaced.
  ///
  /// Only non-null arguments overwrite; use [clear] to empty a compartment.
  PlateSelection copyWith({
    ProteinOption? protein,
    CarbOption? carb,
    FiberOption? fiber,
    PortionScale? scale,
  }) =>
      PlateSelection(
        protein: protein ?? this.protein,
        carb: carb ?? this.carb,
        fiber: fiber ?? this.fiber,
        scale: scale ?? this.scale,
      );

  @override
  String toString() => 'PlateSelection(${scale.name}: '
      '${protein?.id ?? "—"} / ${carb?.id ?? "—"} / ${fiber?.id ?? "—"})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlateSelection &&
          other.protein == protein &&
          other.carb == carb &&
          other.fiber == fiber &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(protein, carb, fiber, scale);
}
