import 'package:flutter/services.dart';

import '../../core/feedback/haptic_cue.dart';
import '../../features/plate_builder/domain/plate_builder_event.dart';

/// The single place a [HapticCue] becomes a platform call.
///
/// The domain names feedback by intent and never imports
/// `package:flutter/services.dart`; this is the one translation. Keeping it
/// to one function matters more than it looks — haptics scattered across
/// widgets is how an app ends up buzzing twice for one tap, which reads as a
/// bug even when nobody can say why.
abstract final class MawzoonHaptics {
  /// Whether haptics are suppressed. Set once at startup from a preference.
  ///
  /// Some guests find continuous selection ticks unpleasant, and on a device
  /// with a poor actuator they are worse than nothing.
  static bool enabled = true;

  /// Plays [cue], or does nothing if [enabled] is false.
  static void play(HapticCue cue) {
    if (!enabled) return;
    switch (cue) {
      case HapticCue.selection:
        HapticFeedback.selectionClick();
      case HapticCue.light:
        HapticFeedback.lightImpact();
      case HapticCue.medium:
        HapticFeedback.mediumImpact();
      case HapticCue.none:
        break;
    }
  }

  /// A tick while a finger moves past a candidate. The lightest cue there is.
  static void selection() => play(HapticCue.selection);

  /// A component committed to a compartment.
  static void light() => play(HapticCue.light);

  /// The balance lock. Reserved for one moment only.
  static void medium() => play(HapticCue.medium);

  /// Routes a domain event to its cue.
  ///
  /// [HapticCue.medium] is deliberately **not** played here. The balance lock
  /// is Tier 4's to fire, from the same call that starts the stroke and the
  /// colour, so the three channels cannot drift apart — see
  /// `BalanceLockChoreography`. The event still carries the cue, because the
  /// event is the record of what happened; this function is only the mapping
  /// used by screens, and a screen that also played it would buzz twice for
  /// one milestone.
  ///
  /// A surface that shows the plate without the canvas — a cart row, a
  /// re-order confirmation — should fire [medium] itself on the same
  /// transition.
  static void forEvent(PlateBuilderEvent event) {
    if (event.haptic == HapticCue.medium) return;
    play(event.haptic);
  }
}
