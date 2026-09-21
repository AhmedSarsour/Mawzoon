import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/nutritional_summary.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/ui_primitives/plate/plate_animation_model.dart';
import 'package:mawzoon/ui_primitives/plate/plate_canvas_painter.dart';
import 'package:mawzoon/ui_primitives/plate/tri_partition_plate.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

NutritionalSummary _summary(
  List<IngredientOption> options, {
  PortionScale scale = PortionScale.standardBalance,
}) =>
    NutritionalSummary.fromComponents(
      scale: scale,
      components: options.map((IngredientOption o) => o.atScale(scale)),
    );

final NutritionalSummary _empty =
    NutritionalSummary.empty(PortionScale.standardBalance);

final NutritionalSummary _partial = _summary(<IngredientOption>[
  MawzoonCatalog.herbGrilledBreast,
]);

final NutritionalSummary _full = _summary(<IngredientOption>[
  MawzoonCatalog.herbGrilledBreast,
  MawzoonCatalog.airFriedSpicedPotatoes,
  MawzoonCatalog.charredGardenVeggies,
]);

/// Hosts the plate for a test.
///
/// The ambient layer breathes on a 16-second loop forever, so a test that
/// calls `pumpAndSettle` would never return with it running. Isolating the
/// plate layer is precisely what the separate RepaintBoundary buys, and the
/// ambient layer gets its own tests below.
Widget _host(
  Widget child, {
  TextDirection direction = TextDirection.rtl,
  bool disableAnimations = false,
}) =>
    MaterialApp(
      theme: AppTheme.dark(fonts: _fonts),
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Center(child: SizedBox(width: 340, child: child)),
          ),
        ),
      ),
    );

void main() {
  group('rendering', () {
    testWidgets('paints an empty plate without throwing',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _empty, showAmbientWarmth: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TriPartitionPlate), findsOneWidget);
    });

    testWidgets('paints a complete plate in both directions',
        (WidgetTester tester) async {
      for (final TextDirection d in TextDirection.values) {
        await tester.pumpWidget(
          _host(TriPartitionPlate(summary: _full, showAmbientWarmth: false), direction: d),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$d');
      }
    });

    testWidgets('paints in the light theme too', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(fonts: _fonts),
          locale: const Locale('en'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: SizedBox(width: 340, child: TriPartitionPlate(summary: _full, showAmbientWarmth: false)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a resize', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _host(
          const SizedBox(width: 220, child: SizedBox.shrink()),
        ),
      );
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('holds its elongated aspect ratio', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pumpAndSettle();
      final Size size = tester.getSize(find.byType(TriPartitionPlate));
      expect(size.width / size.height, closeTo(2.24, 0.01));
    });
  });

  // The performance claim, asserted rather than asserted-in-a-comment.
  group('paint isolation', () {
    testWidgets('each animated layer sits in its own RepaintBoundary',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pumpAndSettle();

      final Finder boundaries = find.descendant(
        of: find.byType(TriPartitionPlate),
        matching: find.byType(RepaintBoundary),
      );
      // Only the plate layer here, since ambient is off; with ambient on the
      // count is two, asserted separately below.
      expect(boundaries, findsOneWidget);
    });

    testWidgets('every CustomPaint sits under a RepaintBoundary',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pumpAndSettle();

      final Iterable<Element> paints = find
          .descendant(
            of: find.byType(TriPartitionPlate),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .where((Element e) {
        final CustomPaint p = e.widget as CustomPaint;
        return p.painter is PlateCanvasPainter ||
            p.painter is AmbientWarmthPainter;
      });
      expect(paints, hasLength(1));

      for (final Element paint in paints) {
        bool foundBoundary = false;
        paint.visitAncestorElements((Element ancestor) {
          if (ancestor.widget is RepaintBoundary) {
            foundBoundary = true;
            return false;
          }
          if (ancestor.widget is TriPartitionPlate) return false;
          return true;
        });
        expect(foundBoundary, isTrue,
            reason: '${paint.widget} is not isolated',);
      }
    });

    testWidgets('animating the plate rebuilds no widget',
        (WidgetTester tester) async {
      // The whole point of passing the model as `repaint:`. If this ever
      // fails, some frame is going through build and the 120 FPS budget is
      // gone.
      int parentBuilds = 0;
      NutritionalSummary current = _empty;
      late StateSetter setOuter;

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              setOuter = setState;
              parentBuilds++;
              return TriPartitionPlate(summary: current, showAmbientWarmth: false);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final int afterFirstSettle = parentBuilds;

      setOuter(() => current = _full);
      await tester.pump();
      final int afterChange = parentBuilds;
      expect(afterChange, afterFirstSettle + 1,
          reason: 'one rebuild for the data change itself',);

      // Now pump the spring animation out. Not one of these frames may build.
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(parentBuilds, afterChange,
          reason: 'the springs must repaint without rebuilding anything',);
      await tester.pumpAndSettle();
    });
  });

  group('motion', () {
    testWidgets('filling the plate runs the springs and then stops ticking',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _empty, showAmbientWarmth: false)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pump();
      // Mid-flight: frames are being produced.
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpAndSettle();
      // Settled: pumpAndSettle only returns when no frames are scheduled, so
      // reaching here at all proves the ticker stopped rather than idling.
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduced motion snaps instead of settling',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(TriPartitionPlate(summary: _empty, showAmbientWarmth: false), disableAnimations: true),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _host(
          TriPartitionPlate(summary: _full, showAmbientWarmth: false),
          disableAnimations: true,
        ),
      );

      // Snapping still costs the one frame that draws the new state — the
      // promise of reduced motion is that there is no *second* frame, not that
      // the plate silently fails to update.
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'reduced motion must reach its final state in one frame',);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ambient runs on its own layer and never settles',
        (WidgetTester tester) async {
      // Deliberately continuous: a 16-second breath. It gets its own
      // RepaintBoundary so it cannot keep the plate layer's ticker alive, and
      // this test uses pump() rather than pumpAndSettle() because a settling
      // ambient layer would mean it had stopped breathing.
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final Finder boundaries = find.descendant(
        of: find.byType(TriPartitionPlate),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundaries, findsNWidgets(2),
          reason: 'ambient and plate must not share a layer',);
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'the ambient breath should still be running',);
      expect(tester.takeException(), isNull);

      // Leave the tree still so the test can finish.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ambient respects reduced motion',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          TriPartitionPlate(summary: _full),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'reduced motion must stop the breath, not just the springs',);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ambient can be switched off entirely',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)),
      );
      await tester.pumpAndSettle();

      final Iterable<CustomPaint> paints = find
          .descendant(
            of: find.byType(TriPartitionPlate),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .map((Element e) => e.widget as CustomPaint);
      expect(
        paints.where((CustomPaint p) => p.painter is AmbientWarmthPainter),
        isEmpty,
      );
    });
  });

  group('accessibility', () {
    testWidgets('announces the plate, not just "image"',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _full, showAmbientWarmth: false)));
      await tester.pumpAndSettle();

      final Semantics node = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(TriPartitionPlate),
              matching: find.byType(Semantics),
            )
            .first,
      );
      final String label = node.properties.label ?? '';
      expect(label, contains('kcal'));
      expect(label, contains('${_full.displayKilocalories}'));
    });

    testWidgets('an unfilled compartment is announced as empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(TriPartitionPlate(summary: _partial, showAmbientWarmth: false)));
      await tester.pumpAndSettle();

      final Semantics node = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(TriPartitionPlate),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.properties.label, contains('—'));
    });

    testWidgets('a caller can override the description',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(TriPartitionPlate(
          summary: _full,
          semanticLabel: 'طبق مكتمل',
          showAmbientWarmth: false,
        ),),
      );
      await tester.pumpAndSettle();
      final Semantics node = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(TriPartitionPlate),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.properties.label, 'طبق مكتمل');
    });
  });

  group('PlateCanvasData', () {
    test('counts what is filled', () {
      final PlateCanvasData data = PlateCanvasData(
        filled: const <bool>[true, true, false],
        energyShares: const <double>[0.5, 0.3, 0],
        compartmentLabels: const <String>['a', 'b', 'c'],
        compartmentDetails: const <String>['', '', ''],
      );
      expect(data.filledCount, 2);
      expect(data.isComplete, isFalse);
      expect(PlateCanvasData.empty.filledCount, 0);
    });

    test('is a value type, so shouldRepaint can trust it', () {
      PlateCanvasData make(List<bool> filled) => PlateCanvasData(
            filled: filled,
            energyShares: const <double>[0.4, 0.35, 0.25],
            compartmentLabels: const <String>['a', 'b', 'c'],
            compartmentDetails: const <String>['x', 'y', 'z'],
          );
      expect(make(const <bool>[true, false, true]),
          make(const <bool>[true, false, true]),);
      expect(make(const <bool>[true, false, true]).hashCode,
          make(const <bool>[true, false, true]).hashCode,);
      expect(make(const <bool>[true, false, true]),
          isNot(make(const <bool>[true, true, true])),);
    });

    test('rejects a plate that is not three compartments', () {
      expect(
        () => PlateCanvasData(
          filled: const <bool>[true, false],
          energyShares: const <double>[1, 0],
          compartmentLabels: const <String>['a', 'b'],
          compartmentDetails: const <String>['', ''],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('PlateSpring', () {
    test('settles at its target', () {
      final PlateSpring s = PlateSpring(0)..target = 1;
      for (int i = 0; i < 400 && !s.isAtRest; i++) {
        s.step(1 / 120);
      }
      expect(s.isAtRest, isTrue);
      expect(s.value, closeTo(1, 1e-3));
    });

    test('retargeting mid-flight keeps momentum rather than jumping', () {
      final PlateSpring s = PlateSpring(0)..target = 1;
      for (int i = 0; i < 10; i++) {
        s.step(1 / 120);
      }
      final double midValue = s.value;
      expect(midValue, greaterThan(0));
      expect(midValue, lessThan(1));

      s.target = 0;
      s.step(1 / 120);
      // Still travelling the old way for an instant: momentum, not a cut.
      expect(s.velocity, greaterThan(0));
    });

    test('a long stalled frame cannot blow the integrator up', () {
      final PlateSpring s = PlateSpring(0)..target = 1;
      s.step(0.5);
      expect(s.value.isFinite, isTrue);
      expect(s.value.abs(), lessThan(4));
    });

    test('snap moves without motion', () {
      final PlateSpring s = PlateSpring(0)
        ..target = 1
        ..step(1 / 60);
      s.snap(0.25);
      expect(s.value, 0.25);
      expect(s.velocity, 0);
      expect(s.isAtRest, isTrue);
    });

    test('impulse kicks and falls back', () {
      final PlateSpring s = PlateSpring(0)..impulse(1);
      expect(s.value, 1);
      expect(s.isAtRest, isFalse);
      for (int i = 0; i < 400 && !s.isAtRest; i++) {
        s.step(1 / 120);
      }
      expect(s.value, closeTo(0, 1e-3));
    });
  });

  group('PlateAnimationModel', () {
    testWidgets('idles until retargeted, then idles again',
        (WidgetTester tester) async {
      late PlateAnimationModel model;
      await tester.pumpWidget(
        _TickerHost(
          onReady: (PlateAnimationModel m) => model = m,
        ),
      );

      expect(model.isTicking, isFalse, reason: 'a still plate costs nothing');

      model.retarget(
        filled: const <bool>[true, false, false],
        arcTargets: const <double>[1, 0, 0],
      );
      expect(model.isTicking, isTrue);

      await tester.pumpAndSettle();
      expect(model.isTicking, isFalse, reason: 'the ticker must stop at rest');
    });

    testWidgets('reduced motion never starts the ticker',
        (WidgetTester tester) async {
      late PlateAnimationModel model;
      await tester.pumpWidget(
        _TickerHost(onReady: (PlateAnimationModel m) => model = m),
      );
      model.reducedMotion = true;
      model.retarget(
        filled: const <bool>[true, true, true],
        arcTargets: const <double>[1, 1, 1],
      );

      expect(model.isTicking, isFalse);
      expect(model.fills[0].value, 1);
      expect(model.fills[2].value, 1);
    });
  });
}

/// A minimal ticker provider host, so the model can be exercised without the
/// whole plate widget around it.
class _TickerHost extends StatefulWidget {
  const _TickerHost({required this.onReady});

  final void Function(PlateAnimationModel) onReady;

  @override
  State<_TickerHost> createState() => _TickerHostState();
}

class _TickerHostState extends State<_TickerHost>
    with TickerProviderStateMixin {
  late final PlateAnimationModel _model;

  @override
  void initState() {
    super.initState();
    _model = PlateAnimationModel(vsync: this);
    widget.onReady(_model);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
