import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// A critically-ish damped spring integrated in place.
///
/// Retargetable mid-flight without a discontinuity: the new simulation starts
/// from wherever the value and velocity currently are, so a guest who swaps
/// protein twice in a second sees one continuous motion rather than two
/// animations fighting.
final class PlateSpring {
  /// Creates a spring resting at [value].
  PlateSpring(double value, {this.stiffness = 330, this.damping = 26})
      : _value = value,
        _target = value;

  /// Spring constant. Higher is snappier.
  final double stiffness;

  /// Damping coefficient. Tuned just under critical, so the settle has a
  /// single almost-imperceptible overshoot rather than a dead stop.
  final double damping;

  double _value;
  double _target;
  double _velocity = 0;

  /// The current value.
  double get value => _value;

  /// Where the spring is heading.
  double get target => _target;

  /// The current velocity, in units per second.
  double get velocity => _velocity;

  /// Whether the spring has settled and no longer needs frames.
  bool get isAtRest =>
      (_value - _target).abs() < _restDistance && _velocity.abs() < _restVelocity;

  static const double _restDistance = 0.0004;
  static const double _restVelocity = 0.0025;

  /// Aims the spring at [next], keeping its current momentum.
  set target(double next) {
    if (next == _target) return;
    _target = next;
  }

  /// Jumps to [next] with no motion. For seeding initial state.
  void snap(double next) {
    _value = next;
    _target = next;
    _velocity = 0;
  }

  /// Kicks the spring to [from] and lets it fall back to its target — the
  /// balance-lock settle.
  void impulse(double from) {
    _value = from;
    _velocity = 0;
  }

  /// The longest span a single [step] will integrate.
  ///
  /// A backgrounded app resumes with an elapsed delta measured in seconds.
  /// Integrating that honestly would fling the spring across the screen, so
  /// the surplus is dropped: the plate resumes from where it was rather than
  /// catching up through a frame nobody saw.
  static const double maxStepSeconds = 0.05;

  /// Advances by [dt] seconds.
  ///
  /// Clamped and then sub-stepped, so neither a dropped frame nor a caller
  /// passing a wild delta can destabilise the integrator. The guard lives here
  /// rather than in the ticker because it is a property of the integrator, not
  /// of one particular caller.
  void step(double dt) {
    if (dt <= 0) return;
    final double span = dt > maxStepSeconds ? maxStepSeconds : dt;
    final int steps = (span / 0.008).ceil().clamp(1, 8);
    final double h = span / steps;
    for (int i = 0; i < steps; i++) {
      final double acceleration =
          -stiffness * (_value - _target) - damping * _velocity;
      _velocity += acceleration * h;
      _value += _velocity * h;
    }
    if (isAtRest) {
      _value = _target;
      _velocity = 0;
    }
  }
}

/// Drives every moving part of the plate canvas from a single ticker.
///
/// This is the object the painter is handed as its `repaint:` argument. That
/// matters more than it looks: a `CustomPainter` given a repaint [Listenable]
/// repaints straight from the paint phase, skipping build and layout
/// entirely. Nothing in the widget tree rebuilds while the plate animates —
/// not the canvas, not the dock, not the carousels. An `AnimatedBuilder`
/// around the canvas would instead rebuild a widget 120 times a second to
/// produce the same pixels.
///
/// The ticker stops itself once every spring is at rest, so an untouched plate
/// costs nothing. Ambient motion deliberately lives in a separate layer rather
/// than here, precisely so that it cannot keep this one awake.
final class PlateAnimationModel extends ChangeNotifier {
  /// Creates a model with all three compartments empty.
  PlateAnimationModel({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  /// Fill of each compartment, 0 when empty and 1 when chosen.
  final List<PlateSpring> fills = <PlateSpring>[
    PlateSpring(0),
    PlateSpring(0),
    PlateSpring(0),
  ];

  /// How far each macro arc has swept, as a fraction of its allotted run.
  final List<PlateSpring> arcs = <PlateSpring>[
    PlateSpring(0),
    PlateSpring(0),
    PlateSpring(0),
  ];

  /// The balance-lock settle: kicked to 1 on completion, springs back to 0.
  final PlateSpring lock = PlateSpring(0, stiffness: 240, damping: 17);

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _reducedMotion = false;

  /// Whether the platform asked for reduced motion.
  ///
  /// Springs then snap instead of settling. The plate still updates — the
  /// information is never withheld — it simply arrives without the travel.
  bool get reducedMotion => _reducedMotion;

  set reducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    if (value) {
      for (final PlateSpring s in _allSprings) {
        s.snap(s.target);
      }
      lock.snap(0);
      _ticker.stop();
      notifyListeners();
    }
  }

  Iterable<PlateSpring> get _allSprings sync* {
    yield* fills;
    yield* arcs;
    yield lock;
  }

  /// Points the compartment springs at [filled] and the arcs at [arcTargets].
  ///
  /// [arcTargets] is each compartment's share of the ring, already computed
  /// from the plate's energy split, so the painter never does nutrition maths.
  void retarget({
    required List<bool> filled,
    required List<double> arcTargets,
  }) {
    assert(filled.length == 3 && arcTargets.length == 3);
    for (int i = 0; i < 3; i++) {
      fills[i].target = filled[i] ? 1 : 0;
      arcs[i].target = arcTargets[i];
    }
    if (_reducedMotion) {
      for (final PlateSpring s in _allSprings) {
        s.snap(s.target);
      }
      notifyListeners();
      return;
    }
    _wake();
  }

  /// Fires the balance-lock settle.
  void strikeLock() {
    if (_reducedMotion) return;
    lock.impulse(1);
    lock.target = 0;
    _wake();
  }

  /// Seeds the springs without animating, for a canvas built mid-plate.
  void seed({required List<bool> filled, required List<double> arcTargets}) {
    for (int i = 0; i < 3; i++) {
      fills[i].snap(filled[i] ? 1 : 0);
      arcs[i].snap(arcTargets[i]);
    }
    lock.snap(0);
    notifyListeners();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;

    for (final PlateSpring s in _allSprings) {
      s.step(dt);
    }

    notifyListeners();

    if (_allSprings.every((PlateSpring s) => s.isAtRest)) {
      _ticker.stop();
    }
  }

  /// Whether frames are currently being produced.
  @visibleForTesting
  bool get isTicking => _ticker.isActive;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
