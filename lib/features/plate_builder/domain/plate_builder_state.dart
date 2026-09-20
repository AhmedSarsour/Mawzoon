import '../../../core/menu/ingredient_option.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import 'plate_selection.dart';

/// The Plate Architect's state machine.
///
/// Three states, one per meaningful moment in the guest's head:
///
///  * [PlateEmpty] — nothing chosen. The canvas shows three ghost
///    compartments and the checkout dock is absent, not disabled.
///  * [PlateConfiguring] — between one and two compartments filled. Macro
///    arcs are live and partial; the balance ring is open.
///  * [PlateBalanced] — all three filled. The ring closes, and this is the
///    only state that can produce a cart line.
///
/// Sealed so that `switch` over the machine is exhaustive at compile time:
/// adding a state later forces every screen to account for it.
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
    if (selection.isComplete) {
      return PlateBalanced(
        protein: selection.protein!,
        carb: selection.carb!,
        fiber: selection.fiber!,
        finalMacros: selection.summary,
      );
    }
    return PlateConfiguring(
      protein: selection.protein,
      carb: selection.carb,
      fiber: selection.fiber,
      currentMacros: selection.summary,
    );
  }

  /// The volume toggle in force.
  PortionScale get scale;

  /// The derived nutrition for this state. Always present, even when empty.
  NutritionalSummary get macros;

  /// The underlying choices, reconstructed from the state.
  PlateSelection get selection;

  /// Whether the plate can be sent to the cart.
  bool get canCheckout => this is PlateBalanced;

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
  /// empty — a fully filled plate is a [PlateBalanced], and a fully empty one
  /// is a [PlateEmpty]. Prefer [PlateBuilderState.from] over calling this.
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
          'A fully filled plate is PlateBalanced, not PlateConfiguring',
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
          other.protein == protein &&
          other.carb == carb &&
          other.fiber == fiber &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(PlateConfiguring, protein, carb, fiber, scale);
}

/// All three compartments are filled — the balance lock.
///
/// Reaching this state is the app's single sensory milestone: the ring closes
/// with a spring settle and one `HapticFeedback.mediumImpact()`. It fires on
/// the *transition* into this state, never on a rebuild, so the controller
/// emits a discrete event rather than letting widgets infer it.
final class PlateBalanced extends PlateBuilderState {
  /// Creates a complete plate.
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
          other.protein == protein &&
          other.carb == carb &&
          other.fiber == fiber &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(PlateBalanced, protein, carb, fiber, scale);
}
