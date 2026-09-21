import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// The four tiers of Mawzoon motion.
///
/// Naming the tier at the call site is the point: it makes "should this move?"
/// a question with an answer. Anything that does not belong to a tier does not
/// move.
enum MotionTier {
  /// Atmosphere. Never reacts to the guest, never stops, never draws the eye.
  ambient,

  /// Structure arriving and leaving: routes, sheets, the plate assembling.
  structural,

  /// The response to a finger on glass.
  tactile,

  /// The single sensory milestone. Spent once per plate.
  milestone,
}

/// Durations, curves and springs, in one place.
///
/// Motion in this app validates intent and offloads cognitive tracking. It is
/// never decorative, so every value here has a reason and a tier, and there is
/// no general-purpose "animation duration" to reach for by default.
abstract final class MawzoonMotion {
  // ---- Tier 1 · Ambient --------------------------------------------------

  /// One full breath of the ambient glow.
  ///
  /// Sixteen seconds is slow enough that the eye never catches it moving,
  /// which is the only speed at which atmosphere stays atmosphere.
  static const Duration ambientBreath = Duration(seconds: 16);

  /// How far the ambient glow swells across a breath.
  static const double ambientScaleRange = 0.06;

  /// Opacity at the bottom and top of a breath.
  static const double ambientMinOpacity = 0.55;

  /// Opacity at the top of a breath.
  static const double ambientMaxOpacity = 1.0;

  // ---- Tier 2 · Structural -----------------------------------------------

  /// The house spring: Newtonian, and slightly underdamped so structure
  /// arrives with one almost-imperceptible settle rather than a dead stop.
  ///
  /// With mass 1 the damping ratio is 30 / (2·√300) ≈ 0.87 — under critical,
  /// which is what makes an arrival feel like an object rather than a fade.
  static const SpringDescription structuralSpring = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 30,
  );

  /// The damping ratio of [structuralSpring], for tests and documentation.
  static double get structuralDampingRatio =>
      structuralSpring.damping /
      (2 * _sqrt(structuralSpring.mass * structuralSpring.stiffness));

  /// How long a structural transition runs before it is considered settled.
  ///
  /// A spring has no natural duration, but a route does: Flutter needs a
  /// `transitionDuration` to schedule against. This is the time the house
  /// spring takes to come to rest, measured rather than guessed.
  static const Duration structuralSettle = Duration(milliseconds: 520);

  /// Below this, a fling is a release rather than a throw.
  static const double flingVelocityThreshold = 320;

  // ---- Tier 3 · Tactile --------------------------------------------------

  /// How far a pressed target compresses.
  ///
  /// The smallest compression that still reads as a response at arm's length.
  /// Deeper starts to look like the element is being swallowed.
  static const double tactileCompression = 0.96;

  /// Compression going down: fast enough to feel like contact, not animation.
  static const Duration tactilePress = Duration(milliseconds: 90);

  /// Release: slower, so the target settles back rather than snapping.
  static const Duration tactileRelease = Duration(milliseconds: 160);

  // ---- Tier 4 · Milestone ------------------------------------------------

  /// How long the balance lock takes to resolve.
  static const Duration balanceLock = Duration(milliseconds: 280);

  /// How far the perimeter stroke thickens when the plate balances.
  static const double lockStrokeGain = 1.5;

  /// How far the macro arcs blend toward Cold-Pressed Olive when locked.
  ///
  /// At 1.0 the ring reads as one equilibrium colour and stops reporting the
  /// energy split by hue. That is the intended trade at the moment of
  /// completion — the compartments below still carry their tones, and the
  /// arc gaps still show the proportions — but it is a token rather than a
  /// literal so the trade can be dialled back without touching the painter.
  static const double lockOliveBlend = 1.0;

  /// The lock's scale overshoot.
  static const double lockSwell = 0.030;

  // ---- Shared ------------------------------------------------------------

  /// Entering: decelerating, as something arriving under its own momentum.
  static const Curve entering = Curves.easeOutCubic;

  /// Leaving: accelerating, as something being dismissed.
  static const Curve leaving = Curves.easeInCubic;

  static double _sqrt(double v) => math.sqrt(v);
}
