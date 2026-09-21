/// Physical feedback, named by intent.
///
/// Lives in `core` because three separate layers need it — the plate domain
/// that emits it, the motion layer that plays it, and the kitchen display
/// that has nothing to do with either. Naming the cue by *intent* rather than
/// by platform API is what keeps the domain free of
/// `package:flutter/services.dart`; the presentation layer maps each cue onto
/// `HapticFeedback` exactly once.
library;

/// The physical feedback a transition deserves.
///
/// Named by *intent*, not by platform API, so the domain layer stays free of
/// `package:flutter/services.dart`. The presentation layer maps each cue onto
/// `HapticFeedback` exactly once.
enum HapticCue {
  /// A light tick while scrolling past candidates — `selectionClick()`.
  selection,

  /// A component committed to a compartment — `lightImpact()`.
  light,

  /// The balance lock. Reserved for one moment only — `mediumImpact()`.
  medium,

  /// No haptic. Silence is a deliberate choice, not an omission.
  none,
}
