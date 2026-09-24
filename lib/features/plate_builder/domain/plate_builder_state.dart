import '../../../core/menu/ingredient_option.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import 'plate_selection.dart';

/// The Plate Architect's state machine.
///
/// Four states, one per meaningful moment in the guest's head:
///
///  * [PlateEmpty] — nothing chosen. The canvas shows three ghost
///    compartments and the checkout dock is absent, not disabled.
///  * [PlateConfiguring] — between one and two compartments filled. Macro
///    arcs are live and partial; the balance ring is open.
///  * [PlateBalanced] — all three filled at the house portion. The ring
///    closes. This is the resting shape of a finished plate.
///  * [PlateVolumeAdjusted] — all three filled, with the volume moved off the
///    house portion to [PortionScale.athleticLoad]. Still a complete,
///    orderable plate; it carries both readings so the dock can show what the
///    adjustment actually cost in energy rather than silently restating a
///    bigger number.
///
/// The four cases partition the space exactly — empty, partial, complete at
/// standard, complete at athletic — so a `switch` over the machine is
/// exhaustive at compile time with no fallthrough, and they are flat siblings
/// rather than a subtype chain so no call site has to get its case order
/// right to be correct.
sealed class PlateBuilderState {
  const PlateBuilderState();

  /// Derives the correct state for [selection].
  ///
  /// This is the single transition function of the machine. The controller
  /// mutates a [PlateSelection] and re-derives; states are never constructed
  /// ad hoc, so an "empty" state carrying a protein is unrepresentable.
  factory PlateBuilderState.from(PlateSelection selection) {
    if (selection.isEmpty) {
      return PlateEmpty(scale: selection.scale);
    }
    if (!selection.isComplete) {
      return PlateConfiguring(
        protein: selection.protein,
        carb: selection.carb,
        fiber: selection.fiber,
        currentMacros: selection.summary,
      );
    }
    if (selection.scale == PortionScale.standardBalance) {
      return PlateBalanced(
        protein: selection.protein!,
        carb: selection.carb!,
        fiber: selection.fiber!,
        finalMacros: selection.summary,
      );
    }
    return PlateVolumeAdjusted(
      protein: selection.protein!,
      carb: selection.carb!,
      fiber: selection.fiber!,
      adjustedMacros: selection.summary,
      baselineMacros: selection
          .copyWith(scale: PortionScale.standardBalance)
          .summary,
    );
  }

  /// The volume toggle in force.
  PortionScale get scale;

  /// The derived nutrition for this state. Always present, even when empty.
  NutritionalSummary get macros;

  /// The underlying choices, reconstructed from the state.
  PlateSelection get selection;

  /// Whether all three compartments are filled.
  ///
  /// True for both complete states. Prefer this over an `is PlateBalanced`
  /// check, which silently excludes a plate on the Athletic Load.
  bool get isComplete => this is PlateBalanced || this is PlateVolumeAdjusted;

  /// Whether the plate can be sent to the cart.
  bool get canCheckout => isComplete;

  /// How many compartments still need a choice, in `0..3`.
  int get remainingSegmentCount => macros.remainingSegmentCount;
}

/// Nothing has been chosen yet.
final class PlateEmpty extends PlateBuilderState {
  /// Creates the empty state at [scale].
  const PlateEmpty({this.scale = PortionScale.standardBalance});

  /// Cached empty summaries, one per scale.
  ///
  /// [PlateEmpty] is const-constructible and therefore cannot memoise on an
  /// instance field, but the canvas reads [macros] every frame while the guest
  /// stares at an untouched plate. Two shared instances cost nothing and keep
  /// that path allocation-free.
  static final Map<PortionScale, NutritionalSummary> _emptySummaries =
      <PortionScale, NutritionalSummary>{
    for (final PortionScale scale in PortionScale.values)
      scale: NutritionalSummary.empty(scale),
  };

  static const Map<PortionScale, PlateSelection> _emptySelections =
      <PortionScale, PlateSelection>{
    PortionScale.standardBalance:
        PlateSelection(scale: PortionScale.standardBalance),
    PortionScale.athleticLoad: PlateSelection(scale: PortionScale.athleticLoad),
  };

  @override
  final PortionScale scale;

  @override
  NutritionalSummary get macros => _emptySummaries[scale]!;

  @override
  PlateSelection get selection => _emptySelections[scale]!;

  @override
  String toString() => 'PlateEmpty(${scale.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PlateEmpty && other.scale == scale;

  @override
  int get hashCode => Object.hash(PlateEmpty, scale);
}

/// One or two compartments are filled; the plate is mid-assembly.
final class PlateConfiguring extends PlateBuilderState {
  /// Creates a partially assembled plate.
  ///
  /// At least one compartment must hold a component and at least one must be
  /// empty — a fully filled plate is a [PlateBalanced] or a
  /// [PlateVolumeAdjusted], and a fully empty one is a [PlateEmpty]. Prefer
  /// [PlateBuilderState.from] over calling this.
  PlateConfiguring({
    this.protein,
    this.carb,
    this.fiber,
    required this.currentMacros,
  })  : assert(
          protein != null || carb != null || fiber != null,
          'PlateConfiguring requires at least one selection; use PlateEmpty',
        ),
        assert(
          protein == null || carb == null || fiber == null,
          'A fully filled plate is PlateBalanced or PlateVolumeAdjusted',
        );

  /// The chosen protein, if any.
  final ProteinOption? protein;

  /// The chosen smart carb, if any.
  final CarbOption? carb;

  /// The chosen vital fibre, if any.
  final FiberOption? fiber;

  /// Live nutrition for the compartments filled so far.
  final NutritionalSummary currentMacros;

  @override
  PortionScale get scale => currentMacros.scale;

  @override
  NutritionalSummary get macros => currentMacros;

  @override
  PlateSelection get selection => PlateSelection(
        protein: protein,
        carb: carb,
        fiber: fiber,
        scale: scale,
      );

  @override
  String toString() =>
      'PlateConfiguring(${macros.filledSegments.length}/3, $currentMacros)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlateConfiguring &&
          _sameMeasurement(other.protein, protein) &&
          _sameMeasurement(other.carb, carb) &&
          _sameMeasurement(other.fiber, fiber) &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(
        PlateConfiguring,
        _measurementHash(protein),
        _measurementHash(carb),
        _measurementHash(fiber),
        scale,
      );
}

/// All three compartments are filled at the house portion — the balance lock.
///
/// Reaching a complete plate is the app's single sensory milestone: the ring
/// closes with a spring settle and one `HapticFeedback.mediumImpact()`. It
/// fires on the *transition* into completeness, never on a rebuild, so the
/// controller emits a discrete event rather than letting widgets infer it.
final class PlateBalanced extends PlateBuilderState {
  /// Creates a complete plate at [PortionScale.standardBalance].
  const PlateBalanced({
    required this.protein,
    required this.carb,
    required this.fiber,
    required this.finalMacros,
  });

  /// The chosen protein.
  final ProteinOption protein;

  /// The chosen smart carb.
  final CarbOption carb;

  /// The chosen vital fibre.
  final FiberOption fiber;

  /// Nutrition for the completed plate.
  final NutritionalSummary finalMacros;

  @override
  PortionScale get scale => finalMacros.scale;

  @override
  NutritionalSummary get macros => finalMacros;

  @override
  PlateSelection get selection => PlateSelection(
        protein: protein,
        carb: carb,
        fiber: fiber,
        scale: scale,
      );

  @override
  String toString() => 'PlateBalanced($finalMacros)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlateBalanced &&
          _sameMeasurement(other.protein, protein) &&
          _sameMeasurement(other.carb, carb) &&
          _sameMeasurement(other.fiber, fiber) &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(
        PlateBalanced,
        _measurementHash(protein),
        _measurementHash(carb),
        _measurementHash(fiber),
        scale,
      );
}

/// A complete plate whose volume has been moved off the house portion.
///
/// The same three components as [PlateBalanced], loaded to
/// [PortionScale.athleticLoad]. It is a distinct state rather than a flag
/// because the screen genuinely differs: the dock shows the delta against the
/// house portion, the ring re-settles, and the plate reads against the
/// athletic band rather than the standard one.
///
/// It carries [baselineMacros] — the identical selection at the house
/// portion — so that difference is computed from the engine rather than
/// re-derived by a widget that might use the wrong factors.
final class PlateVolumeAdjusted extends PlateBuilderState {
  /// Creates a complete plate at an adjusted volume.
  const PlateVolumeAdjusted({
    required this.protein,
    required this.carb,
    required this.fiber,
    required this.adjustedMacros,
    required this.baselineMacros,
  });

  /// The chosen protein.
  final ProteinOption protein;

  /// The chosen smart carb.
  final CarbOption carb;

  /// The chosen vital fibre.
  final FiberOption fiber;

  /// Nutrition at the adjusted volume — what the guest is ordering.
  final NutritionalSummary adjustedMacros;

  /// Nutrition for the same three components at the house portion.
  final NutritionalSummary baselineMacros;

  @override
  PortionScale get scale => adjustedMacros.scale;

  @override
  NutritionalSummary get macros => adjustedMacros;

  @override
  PlateSelection get selection => PlateSelection(
        protein: protein,
        carb: carb,
        fiber: fiber,
        scale: scale,
      );

  /// Extra energy over the house portion, in kilocalories. Always positive.
  double get kilocalorieDelta =>
      adjustedMacros.totalKilocalories - baselineMacros.totalKilocalories;

  /// Extra protein over the house portion, in grams.
  double get proteinGramsDelta =>
      adjustedMacros.totalMacros.proteinGrams -
      baselineMacros.totalMacros.proteinGrams;

  /// Extra plated mass over the house portion, in grams.
  double get portionGramsDelta =>
      adjustedMacros.totalPortionGrams - baselineMacros.totalPortionGrams;

  @override
  String toString() =>
      'PlateVolumeAdjusted($adjustedMacros, +${kilocalorieDelta.round()} kcal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlateVolumeAdjusted &&
          _sameMeasurement(other.protein, protein) &&
          _sameMeasurement(other.carb, carb) &&
          _sameMeasurement(other.fiber, fiber) &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(
        PlateVolumeAdjusted,
        _measurementHash(protein),
        _measurementHash(carb),
        _measurementHash(fiber),
        scale,
      );
}

/// Whether two compartments hold the same choice carrying the same figures.
///
/// [IngredientOption] compares by id, and that is right for what it means:
/// "the guest picked the chicken" is true of the chicken whatever the kitchen
/// last weighed it at. A plate *state* needs a stricter test. When a manager
/// recalibrates a component, the id does not move and the grams do — so an
/// id-only comparison reports the new state equal to the old one, a
/// `ValueNotifier` suppresses the assignment as redundant, and the canvas goes
/// on painting an energy figure the kitchen has superseded.
///
/// Comparing the measurements as well closes that. Absent any calibration the
/// two tests agree exactly, so nothing else in the app changes behaviour.
bool _sameMeasurement(IngredientOption? a, IngredientOption? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a == b &&
      a.basePortionGrams == b.basePortionGrams &&
      a.baseMacros == b.baseMacros;
}

/// A hash that moves when a component is re-measured.
int _measurementHash(IngredientOption? option) => option == null
    ? 0
    : Object.hash(option.id, option.basePortionGrams, option.baseMacros);
