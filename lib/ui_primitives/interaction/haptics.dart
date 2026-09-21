import 'package:flutter/services.dart';

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
  static void forEvent(PlateBuilderEvent event) => play(event.haptic);
}
