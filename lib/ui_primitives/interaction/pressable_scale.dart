import 'package:flutter/material.dart';

import 'haptics.dart';

/// Wraps a tappable thing in the house touch response.
///
/// Two things happen on touch down, together: the target compresses to
/// [pressedScale], and the device ticks. That pairing is the whole point —
/// a visual response without a haptic reads as laggy, and a haptic without a
/// visual response reads as a misfire. Both fire on *down*, not on up, so the
/// acknowledgement arrives while the finger is still on the glass.
///
/// The compression is a [Transform], never a size change, so pressing a chip
/// cannot dirty layout for the row it sits in.
class PressableScale extends StatefulWidget {
  /// Wraps [child] in the house touch response.
  const PressableScale({
    required this.child,
    super.key,
    this.onPressed,
    this.onLongPress,
    this.pressedScale = defaultPressedScale,
    this.cueOnPress = true,
    this.enabled = true,
    this.semanticLabel,
    this.selected = false,
  });

  /// How far a pressed target compresses.
  ///
  /// 0.96 is the smallest compression that still reads as a response at arm's
  /// length. Deeper starts to look like the element is being swallowed.
  static const double defaultPressedScale = 0.96;

  /// How long the compression takes. Fast enough to feel like contact rather
  /// than animation.
  static const Duration pressDuration = Duration(milliseconds: 90);

  /// How long the release takes. Slightly slower, so the target settles back
  /// rather than snapping.
  static const Duration releaseDuration = Duration(milliseconds: 160);

  /// The thing being pressed.
  final Widget child;

  /// Called on a completed tap.
  final VoidCallback? onPressed;

  /// Called on a long press.
  final VoidCallback? onLongPress;

  /// The compressed scale.
  final double pressedScale;

  /// Whether to tick on touch down.
  final bool cueOnPress;

  /// Whether the target responds at all.
  final bool enabled;

  /// A description for screen readers.
  final String? semanticLabel;

  /// Whether this target is currently the selected one.
  final bool selected;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PressableScale.pressDuration,
    reverseDuration: PressableScale.releaseDuration,
  );

  late final Animation<double> _scale = _controller.drive(
    Tween<double>(begin: 1, end: widget.pressedScale)
        .chain(CurveTween(curve: Curves.easeOut)),
  );

  bool get _interactive =>
      widget.enabled && (widget.onPressed != null || widget.onLongPress != null);

  void _press() {
    if (!_interactive) return;
    if (widget.cueOnPress) MawzoonHaptics.selection();
    _controller.forward();
  }

  void _release() {
    if (!_controller.isDismissed) _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _interactive,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        onTap: _interactive ? widget.onPressed : null,
        onLongPress: _interactive ? widget.onLongPress : null,
        // Driving the transform from the animation rather than rebuilding on
        // setState keeps the press off the build phase entirely.
        child: AnimatedBuilder(
          animation: _scale,
          builder: (BuildContext context, Widget? child) => Transform.scale(
            scale: _scale.value,
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
