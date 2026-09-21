import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/feedback/haptic_cue.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';

/// Captures the haptic calls Flutter sends to the platform.
class _Haptics {
  final List<String> calls = <String>[];

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  int count(String type) =>
      calls.where((String c) => c.contains(type)).length;
  void clear() => calls.clear();
}

/// Owns a choreography the way a real widget does.
///
/// The ownership matters: `addTearDown` runs *after* the widget tree is
/// finalized, so a choreography disposed there would still be animating when
/// its TickerProvider goes away — which is a leaked ticker, and the test
/// binding is right to fail on it. A widget that disposes what it created is
/// both the correct pattern and the one that tests cleanly.
class _ChoreographyHost extends StatefulWidget {
  const _ChoreographyHost({required this.onReady});
  final void Function(BalanceLockChoreography) onReady;

  @override
  State<_ChoreographyHost> createState() => _ChoreographyHostState();
}

class _ChoreographyHostState extends State<_ChoreographyHost>
    with TickerProviderStateMixin {
  late final BalanceLockChoreography _lock =
      BalanceLockChoreography(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_lock);
  }

  @override
  void dispose() {
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A bare ticker host, for exercising a controller without a screen.
class _Host extends StatefulWidget {
  const _Host({required this.onReady});
  final void Function(TickerProvider) onReady;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('tokens', () {
    test('the house spring is the one the brief specifies', () {
      expect(MawzoonMotion.structuralSpring.mass, 1);
      expect(MawzoonMotion.structuralSpring.stiffness, 300);
      expect(MawzoonMotion.structuralSpring.damping, 30);
    });

    test('it is underdamped, so structure arrives rather than stops', () {
      // 30 / (2·√300) ≈ 0.866. Above 1 would be a dead stop with no settle.
      expect(MawzoonMotion.structuralDampingRatio, closeTo(0.866, 0.005));
      expect(MawzoonMotion.structuralDampingRatio, lessThan(1));
    });

    test('the tactile compression is 0.96', () {
      expect(MawzoonMotion.tactileCompression, 0.96);
    });

    test('the lock thickens the stroke by 1.5dp', () {
      expect(MawzoonMotion.lockStrokeGain, 1.5);
    });

    test('the ambient breath is 16 seconds', () {
      expect(MawzoonMotion.ambientBreath, const Duration(seconds: 16));
    });

    test('release is slower than press, so targets settle rather than snap',
        () {
      expect(
        MawzoonMotion.tactileRelease,
        greaterThan(MawzoonMotion.tactilePress),
      );
    });
  });

  group('SpringCurve', () {
    test('is anchored at both ends', () {
      final SpringCurve curve = SpringCurve.standard;
      expect(curve.transform(0), closeTo(0, 1e-6));
      expect(curve.transform(1), closeTo(1, 0.02));
    });

    test('overshoots, because the house spring is underdamped', () {
      final SpringCurve curve = SpringCurve.standard;
      double peak = 0;
      for (int i = 0; i <= 100; i++) {
        peak = peak > curve.transform(i / 100) ? peak : curve.transform(i / 100);
      }
      expect(peak, greaterThan(1.0),
          reason: 'an underdamped spring must pass its target once',);
      expect(peak, lessThan(1.15), reason: 'but not bounce like a toy');
    });

    test('really is sampled from a SpringSimulation, not a lookalike cubic',
        () {
      final SpringSimulation reference = SpringSimulation(
        MawzoonMotion.structuralSpring,
        0,
        1,
        0,
      );
      final double seconds = MawzoonMotion.structuralSettle.inMicroseconds /
          Duration.microsecondsPerSecond;
      for (final double t in <double>[0.15, 0.4, 0.7]) {
        expect(
          SpringCurve.standard.transform(t),
          closeTo(reference.x(seconds * t), 0.01),
        );
      }
    });

    test('rises monotonically until it first reaches its target', () {
      double previous = -1;
      for (int i = 0; i <= 40; i++) {
        final double v = SpringCurve.standard.transform(i / 100);
        expect(v, greaterThanOrEqualTo(previous - 1e-9));
        previous = v;
      }
    });
  });

  group('SpringDrive', () {
    test('a decisive throw wins over position', () {
      // Flicked down from near the top: the guest has decided.
      expect(
        SpringDrive.restingTarget(position: 0.9, velocity: 2000),
        0,
      );
      // Flicked up from near the bottom.
      expect(
        SpringDrive.restingTarget(position: 0.1, velocity: -2000),
        1,
      );
    });

    test('a gentle release falls back on position', () {
      expect(SpringDrive.restingTarget(position: 0.7, velocity: 10), 1);
      expect(SpringDrive.restingTarget(position: 0.3, velocity: -10), 0);
    });

    test('classifies a fling by the house threshold', () {
      expect(SpringDrive.isFling(MawzoonMotion.flingVelocityThreshold), isTrue);
      expect(SpringDrive.isFling(-2000), isTrue);
      expect(SpringDrive.isFling(10), isFalse);
    });

    testWidgets('carries the gesture velocity into the simulation',
        (WidgetTester tester) async {
      late TickerProvider vsync;
      await tester.pumpWidget(_Host(onReady: (TickerProvider v) => vsync = v));

      final AnimationController controller =
          AnimationController(vsync: vsync, value: 0.5);
      addTearDown(controller.dispose);

      unawaited(SpringDrive.release(
        controller,
        target: 1,
        velocity: 1800,
        extent: 600,
      ),);
      await tester.pump();
      final double afterFast = controller.value;

      controller.value = 0.5;
      unawaited(SpringDrive.release(
        controller,
        target: 1,
        velocity: 60,
        extent: 600,
      ),);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final double afterSlow = controller.value;

      controller.stop();
      expect(afterFast, isNot(afterSlow),
          reason: 'a fling and a nudge must not animate identically',);
    });

    testWidgets('normalises by extent, so a tall sheet is not faster',
        (WidgetTester tester) async {
      late TickerProvider vsync;
      await tester.pumpWidget(_Host(onReady: (TickerProvider v) => vsync = v));

      Future<double> travel(double extent) async {
        final AnimationController c =
            AnimationController(vsync: vsync, value: 0.5);
        addTearDown(c.dispose);
        unawaited(
          SpringDrive.release(c, target: 1, velocity: 900, extent: extent),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        final double v = c.value;
        c.stop();
        return v;
      }

      // The same thumb speed over a taller sheet covers less of it.
      expect(await travel(300), greaterThan(await travel(900)));
    });
  });

  group('AmbientGlow', () {
    testWidgets('isolates itself and animates only Transform and Opacity',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: AmbientGlow(color: Color(0xFFDE6B35)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AmbientGlow),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AmbientGlow),
          matching: find.byType(Opacity),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AmbientGlow),
          matching: find.byType(Transform),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('builds its gradient once, not per frame',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: AmbientGlow(color: Color(0xFFDE6B35)),
            ),
          ),
        ),
      );
      await tester.pump();

      final DecoratedBox first = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(AmbientGlow),
          matching: find.byType(DecoratedBox),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      final DecoratedBox later = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(AmbientGlow),
          matching: find.byType(DecoratedBox),
        ),
      );

      // The identical widget instance across frames is the proof that the
      // shader is not being rebuilt sixty times a second.
      expect(identical(first, later), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('holds still under reduced motion rather than vanishing',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 200,
                child: AmbientGlow(color: Color(0xFFDE6B35)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(AmbientGlow), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'reduced motion must stop the breath',);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('disposes its controller without leaking a ticker',
        (WidgetTester tester) async {
      // The test binding fails the test if a Ticker outlives its widget, so
      // mounting and unmounting repeatedly is the assertion.
      for (int i = 0; i < 3; i++) {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: AmbientGlow(color: Color(0xFFDE6B35))),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('TactileFeedbackWell', () {
    testWidgets('ticks on the way down, not on release',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TactileFeedbackWell(
                onPressed: () {},
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );
      haptics.clear();

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
      await tester.pump(const Duration(milliseconds: 150));
      expect(haptics.count('selectionClick'), 1,
          reason: 'the tick lands while the finger is still on the glass',);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(haptics.count('selectionClick'), 1,
          reason: 'releasing must not tick a second time',);
    });

    testWidgets('a commitment control can ask for the heavier cue',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TactileFeedbackWell(
                onPressed: () {},
                pressCue: HapticCue.light,
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );
      haptics.clear();

      await tester.tap(find.byType(TactileFeedbackWell));
      await tester.pump(const Duration(milliseconds: 300));
      expect(haptics.count('lightImpact'), 1);
      expect(haptics.count('selectionClick'), 0);
    });

    testWidgets('applies the compression matrix, leaving z untouched',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TactileFeedbackWell(
                onPressed: () {},
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
      // Two frames: the first only starts the ticker at zero elapsed time.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final Matrix4 matrix = tester
          .widgetList<Transform>(find.descendant(
            of: find.byType(TactileFeedbackWell),
            matching: find.byType(Transform),
          ),)
          .last
          .transform;
      expect(matrix.entry(2, 2), 1.0, reason: 'z must not be scaled');

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a disabled well neither ticks nor responds',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      int taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TactileFeedbackWell(
                enabled: false,
                onPressed: () => taps++,
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );
      haptics.clear();

      await tester.tap(find.byType(TactileFeedbackWell));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 0);
      expect(haptics.calls, isEmpty);
    });
  });

  group('BalanceLockChoreography', () {
    Future<BalanceLockChoreography> build(WidgetTester tester) async {
      late BalanceLockChoreography lock;
      await tester.pumpWidget(
        _ChoreographyHost(onReady: (BalanceLockChoreography l) => lock = l),
      );
      return lock;
    }

    testWidgets('fires all three channels from one call',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      final BalanceLockChoreography lock = await build(tester);
      haptics.clear();

      expect(lock.strokeGain, 0);
      expect(lock.oliveBlend, 0);

      lock.lock();
      expect(haptics.count('mediumImpact'), 1,
          reason: 'the haptic fires from the same call as the visuals',);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(lock.strokeGain, closeTo(MawzoonMotion.lockStrokeGain, 0.1));
      expect(lock.oliveBlend, closeTo(1, 0.05));
      expect(lock.isLocked, isTrue);
    });

    testWidgets('is idempotent: a threshold crossed twice is not a threshold',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      final BalanceLockChoreography lock = await build(tester);
      haptics.clear();

      lock
        ..lock()
        ..lock()
        ..lock();
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics.count('mediumImpact'), 1);
    });

    testWidgets('releasing is silent', (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      final BalanceLockChoreography lock = await build(tester);

      lock.lock();
      await tester.pump(const Duration(milliseconds: 400));
      haptics.clear();

      lock.release();
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics.calls, isEmpty,
          reason: 'undoing is not a failure and is not punished',);
      expect(lock.isLocked, isFalse);
      expect(lock.strokeGain, closeTo(0, 0.05));
    });

    testWidgets('re-locking after a release fires again',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      final BalanceLockChoreography lock = await build(tester);
      haptics.clear();

      lock.lock();
      await tester.pump(const Duration(milliseconds: 400));
      lock.release();
      await tester.pump(const Duration(milliseconds: 400));
      lock.lock();
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics.count('mediumImpact'), 2);
    });

    testWidgets('reduced motion keeps the end state, drops the journey',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      final BalanceLockChoreography lock = await build(tester);
      lock.reducedMotion = true;
      haptics.clear();

      lock.lock();
      expect(haptics.count('mediumImpact'), 1,
          reason: 'less motion is not less information',);
      expect(lock.strokeGain, MawzoonMotion.lockStrokeGain);
      expect(lock.oliveBlend, 1);
      expect(lock.isAnimating, isFalse);
    });

    testWidgets('seeding does not fire the milestone',
        (WidgetTester tester) async {
      final _Haptics haptics = _Haptics();
      haptics.install(tester);
      final BalanceLockChoreography lock = await build(tester);
      haptics.clear();

      lock.seed(locked: true);
      expect(haptics.calls, isEmpty,
          reason: 'a plate restored mid-build has not just been completed',);
      expect(lock.strokeGain, MawzoonMotion.lockStrokeGain);
    });

    testWidgets('notifies its listeners as it runs',
        (WidgetTester tester) async {
      final BalanceLockChoreography lock = await build(tester);
      int notifications = 0;
      lock.addListener(() => notifications++);

      lock.lock();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final int midFlight = notifications;

      await tester.pump(const Duration(milliseconds: 400));
      expect(midFlight, greaterThan(1));
      expect(notifications, greaterThan(midFlight));
    });
  });

  // The brief asks for leak guards explicitly. The test binding already fails
  // on a leaked Ticker, so these prove the guards that binding cannot see.
  group('disposal', () {
    testWidgets('a disposed choreography ignores every further call',
        (WidgetTester tester) async {
      late BalanceLockChoreography lock;
      await tester.pumpWidget(
        _ChoreographyHost(onReady: (BalanceLockChoreography l) => lock = l),
      );
      lock.dispose();

      // A late gesture or an in-flight future must not crash the app.
      expect(lock.lock, returnsNormally);
      expect(lock.release, returnsNormally);
      expect(() => lock.seed(locked: true), returnsNormally);
      expect(() => lock.reducedMotion = true, returnsNormally);
      expect(lock.progress, 0);
      expect(lock.isAnimating, isFalse);
    });

    testWidgets('disposing twice is harmless', (WidgetTester tester) async {
      late BalanceLockChoreography lock;
      await tester.pumpWidget(
        _ChoreographyHost(onReady: (BalanceLockChoreography l) => lock = l),
      );
      lock.dispose();
      // And again when the host tears down, which is the realistic case.
      expect(lock.dispose, returnsNormally);
    });

    testWidgets('a well mounted and unmounted repeatedly leaks no ticker',
        (WidgetTester tester) async {
      for (int i = 0; i < 4; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TactileFeedbackWell(
                onPressed: () {},
                child: const SizedBox(width: 80, height: 40),
              ),
            ),
          ),
        );
        final TestGesture gesture = await tester
            .startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
        await tester.pump(const Duration(milliseconds: 40));
        await gesture.up();
        // Torn down mid-animation, which is when a ticker actually leaks.
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(tester.takeException(), isNull);
    });
  });
}
