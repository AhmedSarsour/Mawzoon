import 'package:flutter/material.dart';

import '../../core/feedback/haptic_cue.dart';
import '../interaction/haptics.dart';
import 'motion_tokens.dart';

/// Tier 3 — the house response to a finger on glass.
///
/// Two things happen on touch **down**, together: the target compresses to
/// [MawzoonMotion.tactileCompression], and the device ticks. That pairing is
/// the whole point — a visual response without a haptic reads as laggy, and a
/// haptic without a visual response reads as a misfire. Both fire on the way
/// down, not on release, so the acknowledgement arrives while the finger is
/// still on the glass.
///
/// ## The two cues, and why they are not the same one
///
/// A press is not a commitment. This well fires the *press* cue — a selection
/// tick by default, the lightest thing the actuator can do. The heavier cue
/// belongs to whatever actually accepts the choice, and in this app that is
/// the domain: `PlateBuilderController` emits [HapticCue.light] when a
/// component is committed and [HapticCue.medium] once when the plate locks.
/// Firing a light impact here as well would collapse two distinct events into
/// one buzz, and a control that buzzes identically whether or not it did
/// anything stops being informative.
///
/// A control whose action nothing else acknowledges — a toggle, a dismiss —
/// should pass `pressCue: HapticCue.light` so the tap is felt as a commitment.
///
/// ## Cost
///
/// The compression is a [Transform] built from
/// `Matrix4.diagonal3Values(0.96, 0.96, 1.0)`, driven straight from the
/// animation. It never touches layout, so pressing a chip cannot dirty the
/// row it sits in, and the press does not go through `build`.
class TactileFeedbackWell extends StatefulWidget {
  /// Wraps [child] in the house touch response.
  const TactileFeedbackWell({
    required this.child,
    super.key,
    this.onPressed,
    this.onLongPress,
    this.pressedScale = MawzoonMotion.tactileCompression,
    this.pressCue = HapticCue.selection,
    this.enabled = true,
    this.semanticLabel,
    this.selected = false,
  });

  /// The thing being pressed.
  final Widget child;

  /// Called on a completed tap.
  final VoidCallback? onPressed;

  /// Called on a long press.
  final VoidCallback? onLongPress;

  /// The compressed scale.
  final double pressedScale;

  /// What the device does on touch down.
  ///
  /// [HapticCue.selection] by default — see the class doc for why this is not
  /// a light impact.
  final HapticCue pressCue;

  /// Whether the target responds at all.
  final bool enabled;

  /// A description for screen readers.
  final String? semanticLabel;

  /// Whether this target is currently the selected one.
  final bool selected;

  @override
  State<TactileFeedbackWell> createState() => _TactileFeedbackWellState();
}

class _TactileFeedbackWellState extends State<TactileFeedbackWell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: MawzoonMotion.tactilePress,
    reverseDuration: MawzoonMotion.tactileRelease,
  );

  late final Animation<double> _scale = _press.drive(
    Tween<double>(begin: 1, end: widget.pressedScale)
        .chain(CurveTween(curve: Curves.easeOut)),
  );

  bool get _interactive =>
      widget.enabled && (widget.onPressed != null || widget.onLongPress != null);

  void _down() {
    if (!_interactive) return;
    MawzoonHaptics.play(widget.pressCue);
    _press.forward();
  }

  void _up() {
    if (!_press.isDismissed) _press.reverse();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _interactive,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      // A summary label replaces the subtree it summarises rather than being
      // prepended to it. Without this, a station row reads as "Grill, Smoked
      // Entrecôte, 140 grams" and then reads "Grill", "140 g", "Smoked
      // Entrecôte", "Flame seared", "Medium rare" all over again — the well's
      // whole reason for taking a label is to say the useful version once.
      // A well given no label keeps its children, which is the only way an
      // unlabelled one is readable at all.
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: _interactive ? widget.onPressed : null,
        onLongPress: _interactive ? widget.onLongPress : null,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (BuildContext context, Widget? child) => Transform(
            alignment: Alignment.center,
            // The brief's matrix, written out: a uniform compression in x and
            // y with z untouched, so nothing acquires false perspective.
            transform: Matrix4.diagonal3Values(_scale.value, _scale.value, 1),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
