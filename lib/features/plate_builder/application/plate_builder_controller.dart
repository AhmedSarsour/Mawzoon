import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/nutritional_summary.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../domain/plate_builder_event.dart';
import '../domain/plate_builder_state.dart';
import '../domain/plate_selection.dart';

/// Drives the Plate Architect.
///
/// A [ValueNotifier] rather than a heavyweight store: the tri-partition canvas
/// repaints at 120 Hz against this value, and every layer of indirection
/// between a tap and a frame is a dropped frame waiting to happen. Widgets
/// subscribe with `ValueListenableBuilder` scoped as tightly as possible so a
/// protein swap never rebuilds the checkout dock.
///
/// State is always *derived* from [selection] through
/// [PlateBuilderState.from]. There is no code path that constructs a state
/// directly, so the machine cannot enter an inconsistent configuration.
final class PlateBuilderController extends ValueNotifier<PlateBuilderState> {
  /// Creates a controller, optionally seeded with an existing selection —
  /// a re-order, a deep link, or a curated signature plate the guest chose to
  /// customise.
  PlateBuilderController({PlateSelection initialSelection = PlateSelection.empty})
      : _selection = initialSelection,
        super(PlateBuilderState.from(initialSelection));

  final StreamController<PlateBuilderEvent> _events =
      StreamController<PlateBuilderEvent>.broadcast();

  PlateSelection _selection;

  /// One-shot transitions: haptics, sound, analytics.
  ///
  /// Broadcast, so the canvas, the dock and the telemetry layer can each
  /// listen without fighting over the subscription.
  Stream<PlateBuilderEvent> get events => _events.stream;

  /// The guest's current raw choices.
  PlateSelection get selection => _selection;

  /// Live nutrition for the current selection.
  NutritionalSummary get macros => value.macros;

  /// The volume toggle in force.
  PortionScale get scale => _selection.scale;

  /// Whether the plate is complete and can be sent to the cart.
  bool get canCheckout => value.canCheckout;

  /// Places [option] into its own compartment.
  ///
  /// Selecting the component that is already there is a no-op: no state
  /// change, no event, no haptic. Tapping a chosen item should feel inert
  /// rather than re-confirming something the guest can already see.
  void select(IngredientOption option) {
    final IngredientOption? existing = _selection.optionFor(option.segment);
    if (existing == option) return;

    _apply(
      _selection.select(option),
      SegmentFilled(option: option, replaced: existing),
    );
  }

  /// Empties [segment]. A no-op when the compartment is already empty.
  void clearSegment(PlateSegment segment) {
    final IngredientOption? existing = _selection.optionFor(segment);
    if (existing == null) return;

    _apply(
      _selection.clear(segment),
      SegmentCleared(segment: segment, removed: existing),
    );
  }

  /// Sets the volume toggle. A no-op when already at [scale].
  void setScale(PortionScale scale) {
    if (_selection.scale == scale) return;
    _apply(_selection.copyWith(scale: scale), ScaleChanged(scale: scale));
  }

  /// Flips the volume toggle.
  void toggleScale() => setScale(_selection.scale.toggled);

  /// Replaces the whole selection at once.
  ///
  /// Used when a guest opens a curated signature plate in the Architect. The
  /// balance lock fires if this completes the plate, because from the guest's
  /// point of view the plate did just come together.
  void replaceSelection(PlateSelection next) {
    if (next == _selection) return;
    _apply(next, null);
  }

  /// Returns the plate to empty, keeping the volume toggle where the guest
  /// left it — the scale is a standing preference, not part of the meal.
  void reset() {
    if (_selection.isEmpty) return;
    _apply(PlateSelection(scale: _selection.scale), const PlateReset());
  }

  /// Applies [next], re-derives the state, and emits [event] plus any
  /// threshold event the transition crossed.
  void _apply(PlateSelection next, PlateBuilderEvent? event) {
    final bool wasComplete = value.isComplete;
    _selection = next;

    final PlateBuilderState derived = PlateBuilderState.from(next);
    value = derived;

    if (event != null) _emit(event);

    // The lock is keyed on completeness, not on PlateBalanced specifically.
    // Moving a finished plate to the Athletic Load changes the state class but
    // not the fact that the plate is done, so it must not re-fire the
    // milestone — and completing a plate that is already on the Athletic Load
    // must still fire it.
    final bool isComplete = derived.isComplete;
    if (isComplete && !wasComplete) {
      _emit(BalanceLocked(summary: derived.macros));
    } else if (wasComplete && !isComplete) {
      _emit(const BalanceReleased());
    }
  }

  void _emit(PlateBuilderEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  @override
  void dispose() {
    unawaited(_events.close());
    super.dispose();
  }
}
