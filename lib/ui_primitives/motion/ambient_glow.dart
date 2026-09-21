import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Tier 1 — the ambient warmth behind the hero plate.
///
/// A radial glow that breathes on a 16-second cycle. It is the only thing in
/// the app that moves without being asked to, which is why it is held to the
/// strictest budget of anything here.
///
/// ## Why this costs nothing
///
/// The gradient is built **once**, as a decoration on a child that the
/// animation never rebuilds. Each frame changes only a [Transform] and an
/// [Opacity] — no shader is recreated, no layout runs, and no widget below
/// this one is rebuilt. Painting a `RadialGradient` per frame, which is the
/// obvious way to write this, allocates a new shader sixty to a hundred and
/// twenty times a second for a glow nobody is looking at directly.
///
/// The whole thing sits in its own [RepaintBoundary] so a layer that never
/// stops animating cannot drag the rest of the screen into repainting with
/// it. That isolation is also what lets the interactive layers above go
/// completely idle — see the note in `TriPartitionPlate`.
///
/// Under `MediaQuery.disableAnimations` it holds still at mid-breath rather
/// than disappearing: the warmth is part of the composition, not an effect.
class AmbientGlow extends StatefulWidget {
  /// Creates the ambient layer.
  const AmbientGlow({
    required this.color,
    super.key,
    this.radiusFactor = 0.62,
    this.baseOpacity = 0.09,
  });

  /// The glow's hue. Roasted Ember, at the call site's discretion.
  final Color color;

  /// Radius as a fraction of the box's width.
  final double radiusFactor;

  /// Peak opacity at the centre of the glow.
  final double baseOpacity;

  @override
  State<AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<AmbientGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: MawzoonMotion.ambientBreath,
  );

  late final CurvedAnimation _wave = CurvedAnimation(
    parent: _breath,
    curve: Curves.easeInOut,
  );

  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _breath.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced == _reduced) return;
    _reduced = reduced;
    if (reduced) {
      // Held at mid-breath rather than removed: the warmth is composition.
      _breath
        ..stop()
        ..value = 0.5;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    // CurvedAnimation holds a listener on its parent; disposing it before the
    // controller is what keeps this from leaking when the plate is rebuilt.
    _wave.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _wave,
          builder: (BuildContext context, Widget? child) {
            final double t = _wave.value;
            return Opacity(
              opacity: MawzoonMotion.ambientMinOpacity +
                  (MawzoonMotion.ambientMaxOpacity -
                          MawzoonMotion.ambientMinOpacity) *
                      t,
              child: Transform.scale(
                scale: 1 + MawzoonMotion.ambientScaleRange * t,
                child: child,
              ),
            );
          },
          // Built once. The animation above never rebuilds this subtree, so
          // the gradient shader is created a single time.
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: widget.radiusFactor,
                colors: <Color>[
                  widget.color.withValues(alpha: widget.baseOpacity),
                  widget.color.withValues(alpha: 0),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
