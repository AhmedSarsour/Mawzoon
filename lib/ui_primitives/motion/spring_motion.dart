import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion_tokens.dart';

/// A [Curve] sampled from a real [SpringSimulation].
///
/// Flutter's route machinery wants a curve and a duration; Newtonian motion
/// wants neither. This bridges them honestly: the shape really is the house
/// spring's displacement over time, sampled once at construction and read back
/// by interpolation, rather than a cubic chosen because it looks springy.
///
/// It cannot inherit velocity — a curve has no memory — so anything released
/// from a drag should use [SpringDrive] instead. This is for arrivals that
/// begin at rest, which is most of them.
class SpringCurve extends Curve {
  /// Samples [spring] over [duration] into [samples] points.
  SpringCurve({
    SpringDescription spring = MawzoonMotion.structuralSpring,
    Duration duration = MawzoonMotion.structuralSettle,
    int samples = 120,
  })  : assert(samples > 1, 'a curve needs at least two samples'),
        _samples = _sample(spring, duration, samples);

  /// The house spring, sampled at the house settle time.
  static final SpringCurve standard = SpringCurve();

  final List<double> _samples;

  static List<double> _sample(
    SpringDescription spring,
    Duration duration,
    int samples,
  ) {
    final SpringSimulation simulation =
        SpringSimulation(spring, 0, 1, 0);
    final double seconds =
        duration.inMicroseconds / Duration.microsecondsPerSecond;
    return List<double>.generate(
      samples,
      (int i) => simulation.x(seconds * i / (samples - 1)),
      growable: false,
    );
  }

  @override
  double transformInternal(double t) {
    final double position = t * (_samples.length - 1);
    final int low = position.floor().clamp(0, _samples.length - 1);
    final int high = position.ceil().clamp(0, _samples.length - 1);
    if (low == high) return _samples[low];
    return _samples[low] + (_samples[high] - _samples[low]) * (position - low);
  }

  @override
  String toString() => 'SpringCurve(${_samples.length} samples)';
}

/// Drives a controller with a spring that inherits the gesture's velocity.
///
/// This is the half a [Curve] cannot do. When a guest flings a sheet, the
/// sheet should keep travelling at the speed their thumb left it at; an
/// animation that restarts from zero velocity feels like the app dropped the
/// gesture and started its own, separate idea of the motion.
abstract final class SpringDrive {
  /// Releases [controller] toward [target] carrying [velocity].
  ///
  /// [velocity] is in logical pixels per second, as reported by a drag's
  /// `primaryVelocity`. It is converted into the controller's 0..1 space by
  /// [extent], the distance the controller spans — without that division a
  /// fling on a tall sheet and a fling on a short one would behave completely
  /// differently for the same thumb speed.
  static TickerFuture release(
    AnimationController controller, {
    required double target,
    required double velocity,
    required double extent,
    SpringDescription spring = MawzoonMotion.structuralSpring,
  }) {
    assert(extent > 0, 'extent must be positive');
    final double normalised = velocity / extent;
    return controller.animateWith(
      SpringSimulation(spring, controller.value, target, normalised),
    );
  }

  /// Whether [velocity] counts as a throw rather than a release.
  static bool isFling(double velocity) =>
      velocity.abs() >= MawzoonMotion.flingVelocityThreshold;

  /// Where a drag released at [velocity] from [position] should land.
  ///
  /// A decisive throw wins over position: a guest who flicks a sheet downward
  /// from near the top means to dismiss it, and fighting that with a
  /// "you were still mostly open" rule is how a gesture starts feeling sticky.
  static double restingTarget({
    required double position,
    required double velocity,
  }) {
    if (isFling(velocity)) return velocity > 0 ? 0 : 1;
    return position >= 0.5 ? 1 : 0;
  }
}

/// Tier 2 — a route that arrives on the house spring.
///
/// The page rises and settles rather than sliding linearly into place. Under
/// `MediaQuery.disableAnimations` it cuts straight in, because a guest who
/// asked for less motion did not ask for slower motion.
class SpringPageRoute<T> extends PageRouteBuilder<T> {
  /// Creates a spring-driven route for [child].
  SpringPageRoute({
    required Widget child,
    super.settings,
  }) : super(
          transitionDuration: MawzoonMotion.structuralSettle,
          reverseTransitionDuration: MawzoonMotion.tactileRelease,
          pageBuilder: (_, __, ___) => child,
          transitionsBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
            Widget page,
          ) {
            if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
              return page;
            }
            final Animation<double> sprung = CurvedAnimation(
              parent: animation,
              curve: SpringCurve.standard,
              reverseCurve: MawzoonMotion.leaving,
            );
            return FadeTransition(
              opacity: animation.drive(
                Tween<double>(begin: 0, end: 1)
                    .chain(CurveTween(curve: const Interval(0, 0.45))),
              ),
              child: AnimatedBuilder(
                animation: sprung,
                builder: (BuildContext context, Widget? built) =>
                    Transform.translate(
                  // Translate, never a layout offset: a route transition that
                  // re-runs layout every frame is the most expensive thing an
                  // app can do while the guest is watching.
                  offset: Offset(
                    0,
                    (1 - sprung.value) *
                        MediaQuery.sizeOf(context).height *
                        travelFraction,
                  ),
                  child: built,
                ),
                child: page,
              ),
            );
          },
        );

  /// How far the page travels on entry, as a fraction of screen height.
  ///
  /// A constant rather than a constructor argument: the transitions builder
  /// passed to `super` is a static closure and cannot see instance state, so a
  /// per-route field here would be settable and silently ignored.
  static const double travelFraction = 0.06;
}
