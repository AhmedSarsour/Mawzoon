import '../../../core/feedback/haptic_cue.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';

/// A discrete thing that happened to the plate.
///
/// Events exist so that one-shot effects — a haptic, a sound, an analytics
/// hit, a confetti-free ring settle — fire on a *transition* rather than on
/// every rebuild. A widget that infers "we just balanced" by comparing states
/// will eventually fire twice; an event fires once.
sealed class PlateBuilderEvent {
  const PlateBuilderEvent();

  /// The haptic this event should trigger.
  HapticCue get haptic;
}

/// A component was placed into a compartment.
final class SegmentFilled extends PlateBuilderEvent {
  /// Creates a fill event.
  const SegmentFilled({required this.option, required this.replaced});

  /// The component that was placed.
  final IngredientOption option;

  /// The component it displaced, if the compartment was already occupied.
  final IngredientOption? replaced;

  /// Which compartment received the component.
  PlateSegment get segment => option.segment;

  @override
  HapticCue get haptic => HapticCue.light;

  @override
  String toString() => 'SegmentFilled(${option.id})';
}

/// A compartment was emptied.
final class SegmentCleared extends PlateBuilderEvent {
  /// Creates a clear event.
  const SegmentCleared({required this.segment, required this.removed});

  /// The compartment that was emptied.
  final PlateSegment segment;

  /// The component that was removed.
  final IngredientOption removed;

  @override
  HapticCue get haptic => HapticCue.light;

  @override
  String toString() => 'SegmentCleared(${segment.name})';
}

/// The volume toggle flipped.
final class ScaleChanged extends PlateBuilderEvent {
  /// Creates a scale event.
  const ScaleChanged({required this.scale});

  /// The scale now in force.
  final PortionScale scale;

  @override
  HapticCue get haptic => HapticCue.light;

  @override
  String toString() => 'ScaleChanged(${scale.name})';
}

/// All three compartments became filled — the sensory milestone.
///
/// Fires only on entry into `PlateBalanced`. Swapping one protein for another
/// on an already-balanced plate does **not** re-fire it; the lock is a
/// threshold, and re-crossing it every tap would cheapen the moment.
final class BalanceLocked extends PlateBuilderEvent {
  /// Creates a lock event.
  const BalanceLocked({required this.summary});

  /// The completed plate's nutrition.
  final NutritionalSummary summary;

  @override
  HapticCue get haptic => HapticCue.medium;

  @override
  String toString() => 'BalanceLocked($summary)';
}

/// A balanced plate lost a compartment and is being assembled again.
///
/// Silent by design: undoing is not a failure and should not be punished with
/// a buzz.
final class BalanceReleased extends PlateBuilderEvent {
  /// Creates a release event.
  const BalanceReleased();

  @override
  HapticCue get haptic => HapticCue.none;

  @override
  String toString() => 'BalanceReleased()';
}

/// The plate was reset to empty.
final class PlateReset extends PlateBuilderEvent {
  /// Creates a reset event.
  const PlateReset();

  @override
  HapticCue get haptic => HapticCue.light;

  @override
  String toString() => 'PlateReset()';
}
