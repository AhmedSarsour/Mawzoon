import 'package:flutter/material.dart';

import '../interaction/haptics.dart';
import 'motion_tokens.dart';
import 'spring_motion.dart';

/// Tier 4 — the balance lock, orchestrated.
///
/// The app's single sensory milestone, and the only place three channels fire
/// together: the perimeter macro stroke thickens by
/// [MawzoonMotion.lockStrokeGain], the arcs transition to Cold-Pressed Olive,
/// and the device delivers one crisp `mediumImpact`.
///
/// ## Why this is an object and not three `setState` calls
///
/// The three channels have to agree. If the haptic fires on a state change
/// while the stroke animates from a controller and the colour comes from an
/// implicit animation, they drift apart on a loaded frame and the moment
/// reads as three separate small events instead of one. Here a single
/// controller drives all three, and the haptic is fired by the same call that
/// starts it.
///
/// ## Once, on the crossing
///
/// [lock] is idempotent while locked. Swapping a protein on an already
/// balanced plate does not re-fire the milestone: a threshold crossed twice
/// is not a threshold. [release] returns the choreography to rest silently —
/// undoing is not a failure and is not punished with a buzz.
class BalanceLockChoreography extends ChangeNotifier {
  /// Creates the choreography.
  ///
  /// [vsync] is usually the widget's own `TickerProvider`; the controller is
  /// owned here and disposed with this object.
  BalanceLockChoreography({required TickerProvider vsync}) {
    _controller = AnimationController(
      vsync: vsync,
      duration: MawzoonMotion.balanceLock,
      reverseDuration: MawzoonMotion.tactileRelease,
    )..addListener(_onTick);
  }

  late final AnimationController _controller;
  late final Animation<double> _sprung = _controller.drive(
    CurveTween(curve: SpringCurve.standard),
  );

  bool _locked = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  /// Whether the plate is currently balanced.
  bool get isLocked => _locked;

  /// The choreography's progress, `0.0` at rest and `1.0` fully locked.
  ///
  /// Read by the painter every frame. It overshoots slightly on the way in,
  /// because the house spring is deliberately underdamped.
  double get progress => _disposed ? 0 : _sprung.value;

  /// Extra stroke width for the perimeter macro arcs, in logical pixels.
  double get strokeGain => MawzoonMotion.lockStrokeGain * progress;

  /// How far the arcs have blended toward Cold-Pressed Olive, `0.0..1.0`.
  double get oliveBlend =>
      (MawzoonMotion.lockOliveBlend * progress).clamp(0.0, 1.0);

  /// Whether any channel is currently mid-flight.
  bool get isAnimating => !_disposed && _controller.isAnimating;

  /// Suppresses the travel, keeping the end states.
  ///
  /// A guest who asked for less motion still gets the lock — the stroke, the
  /// colour and the haptic — it simply arrives without the journey.
  set reducedMotion(bool value) {
    if (_reducedMotion == value || _disposed) return;
    _reducedMotion = value;
    if (value && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = _locked ? 1 : 0;
      notifyListeners();
    }
  }

  /// Fires the milestone. Idempotent while already locked.
  void lock() {
    if (_disposed || _locked) return;
    _locked = true;

    // The haptic is fired by the same call that starts the visual channels,
    // so the three cannot drift apart on a loaded frame.
    MawzoonHaptics.medium();

    if (_reducedMotion) {
      _controller.value = 1;
      notifyListeners();
      return;
    }
    _controller.forward(from: 0);
  }

  /// Returns to rest. Silent by design.
  void release() {
    if (_disposed || !_locked) return;
    _locked = false;
    if (_reducedMotion) {
      _controller.value = 0;
      notifyListeners();
      return;
    }
    _controller.reverse();
  }

  /// Sets the locked state without animating, for a canvas built mid-plate.
  void seed({required bool locked}) {
    if (_disposed) return;
    _locked = locked;
    _controller.value = locked ? 1 : 0;
    notifyListeners();
  }

  void _onTick() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    // Guarded rather than trusted: a late tick arriving after teardown is a
    // crash in release and a confusing assertion in debug, and the controller
    // is the one thing here that can outlive the widget that made it.
    if (_disposed) return;
    _disposed = true;
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }
}
