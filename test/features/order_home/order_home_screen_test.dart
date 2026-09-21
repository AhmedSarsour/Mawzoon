import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';
import 'package:mawzoon/features/curated_menu/presentation/curated_track.dart';
import 'package:mawzoon/features/order_home/presentation/order_home_screen.dart';
import 'package:mawzoon/features/plate_builder/application/plate_builder_controller.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_builder_state.dart';
import 'package:mawzoon/features/plate_builder/presentation/plate_architect_track.dart';
import 'package:mawzoon/ui_primitives/controls/macro_capsule.dart';
import 'package:mawzoon/ui_primitives/controls/volume_toggle.dart';
import 'package:mawzoon/ui_primitives/interaction/haptics.dart';
import 'package:mawzoon/ui_primitives/plate/tri_partition_plate.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();
const Size _phone = Size(390, 844);

/// Captures the haptic calls Flutter sends to the platform, so the
/// micro-interaction requirement is verified rather than assumed.
class HapticRecorder {
  final List<String> calls = <String>[];

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  int get selectionClicks =>
      calls.where((String c) => c.contains('selectionClick')).length;
  int get lightImpacts =>
      calls.where((String c) => c.contains('lightImpact')).length;
  int get mediumImpacts =>
      calls.where((String c) => c.contains('mediumImpact')).length;
  void clear() => calls.clear();
}

Widget _app({
  PlateBuilderController? controller,
  OrderTrack track = OrderTrack.curated,
  AppLanguage language = AppLanguage.arabic,
}) =>
    MaterialApp(
      theme: AppTheme.dark(language: language, fonts: _fonts),
      locale: Locale(language.code),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      home: OrderHomeScreen(
        key: ValueKey<OrderTrack>(track),
        controller: controller,
        initialTrack: track,
      ),
    );

Future<void> _pumpPhone(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 400));
}

/// The bounding box of the painted (non-black) pixels inside the boundary.
///
/// Rendering to an image is the only way to observe a Transform applied inside
/// an AnimatedBuilder that the widget tree does not report faithfully.
Future<Size> _paintedExtent(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(const Key('boundary')));
  late ByteData data;
  late ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage();
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });

  int minX = image.width, maxX = -1, minY = image.height, maxY = -1;
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final int i = (y * image.width + x) * 4;
      // Anything meaningfully brighter than the black ground counts as paint.
      if (data.getUint8(i) > 128) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  image.dispose();
  if (maxX < 0) return Size.zero;
  return Size((maxX - minX + 1).toDouble(), (maxY - minY + 1).toDouble());
}

void main() {
  group('the screen opens on the fast path', () {
    testWidgets('curated is the default track', (WidgetTester tester) async {
      await _pumpPhone(tester, _app());
      expect(find.byType(CuratedTrack), findsOneWidget);
      expect(find.byType(PlateArchitectTrack), findsNothing);
    });

    testWidgets('the plate and the dock are always present',
        (WidgetTester tester) async {
      await _pumpPhone(tester, _app());
      expect(find.byType(MacroCapsule), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the architect track can be opened directly',
        (WidgetTester tester) async {
      await _pumpPhone(tester, _app(track: OrderTrack.architect));
      expect(find.byType(PlateArchitectTrack), findsOneWidget);
      expect(find.byType(CuratedTrack), findsNothing);
    });
  });

  // "Put the selectors in the thumb zone" is exactly the kind of intention
  // that quietly stops being true the first time a row is added.
  group('thumb zone', () {
    testWidgets('every carousel sits in the lower half of a phone',
        (WidgetTester tester) async {
      for (final OrderTrack track in OrderTrack.values) {
        await _pumpPhone(tester, _app(track: track));
        final double midpoint = _phone.height / 2;

        final Finder carousel = track == OrderTrack.curated
            ? find.byType(CuratedTrack)
            : find.byType(PlateArchitectTrack);
        final Rect box = tester.getRect(carousel);

        expect(box.top, greaterThanOrEqualTo(midpoint),
            reason: '$track starts at ${box.top.toStringAsFixed(0)}, above the '
                'midpoint at ${midpoint.toStringAsFixed(0)}',);
      }
    });

    testWidgets('the dock owns the bottom of the screen',
        (WidgetTester tester) async {
      await _pumpPhone(tester, _app());

      // Measured on the card itself, not on MacroCapsule — that includes the
      // outer padding that produces the float in the first place.
      final Rect card = tester.getRect(
        find
            .descendant(
              of: find.byType(MacroCapsule),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );

      // It floats: inset from every edge rather than flush against the
      // bottom, so it reads as a control resting on the page rather than
      // chrome the page ends at.
      expect(card.bottom, lessThan(_phone.height));
      expect(card.bottom, greaterThan(_phone.height - 64));
      expect(card.top, greaterThan(_phone.height / 2),
          reason: 'the dock must sit inside the thumb zone',);
      expect(card.left, greaterThan(0));
      expect(card.right, lessThan(_phone.width));
    });

    testWidgets('the plate stays above the thumb zone',
        (WidgetTester tester) async {
      await _pumpPhone(tester, _app());
      final Rect plate = tester.getRect(find.byType(TriPartitionPlate));
      expect(plate.bottom, lessThan(_phone.height / 2));
    });
  });

  group('micro-interactions', () {
    testWidgets('a touch compresses the target to 0.96',
        (WidgetTester tester) async {
      // Measured from rendered pixels, not from the widget tree. The
      // compression is applied inside an AnimatedBuilder, and reading the
      // resulting Transform back out proved unreliable — the builder
      // demonstrably receives the animated value while the finder returns an
      // identity matrix. Pixels are what the guest sees, so pixels are what
      // this asserts.
      await tester.binding.setSurfaceSize(const Size(300, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF000000),
            body: Center(
              child: RepaintBoundary(
                key: const Key('boundary'),
                child: TactileFeedbackWell(
                  onPressed: () {},
                  child: Container(
                    width: 180,
                    height: 90,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Size resting = await _paintedExtent(tester);
      expect(resting.width, greaterThan(0));

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
      // Two frames: the first only starts the ticker at zero elapsed time.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      final Size pressed = await _paintedExtent(tester);
      expect(
        pressed.width / resting.width,
        closeTo(MawzoonMotion.tactileCompression, 0.01),
        reason: 'pressed ${pressed.width} vs resting ${resting.width}',
      );
      expect(
        pressed.height / resting.height,
        closeTo(MawzoonMotion.tactileCompression, 0.01),
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));

      final Size released = await _paintedExtent(tester);
      expect(released.width / resting.width, closeTo(1.0, 0.01),
          reason: 'and settle back on release',);
    });

    testWidgets('a cancelled touch springs back without firing the action',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(fonts: _fonts),
          home: Scaffold(
            body: Center(
              child: TactileFeedbackWell(
                onPressed: () => taps++,
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(taps, 0);
      expect(
        tester
            .widget<Transform>(
              find.descendant(
                of: find.byType(TactileFeedbackWell),
                matching: find.byType(Transform),
              ),
            )
            .transform
            .getMaxScaleOnAxis(),
        closeTo(1.0, 1e-3),
      );
    });

    testWidgets('a disabled target neither compresses nor ticks',
        (WidgetTester tester) async {
      final HapticRecorder haptics = HapticRecorder();
      haptics.install(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(fonts: _fonts),
          home: const Scaffold(
            body: Center(
              child: TactileFeedbackWell(
                enabled: false,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );
      haptics.clear();

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(TactileFeedbackWell)));
      await tester.pump(const Duration(milliseconds: 150));

      expect(haptics.calls, isEmpty);
      expect(
        tester
            .widget<Transform>(
              find.descendant(
                of: find.byType(TactileFeedbackWell),
                matching: find.byType(Transform),
              ),
            )
            .transform
            .getMaxScaleOnAxis(),
        closeTo(1.0, 1e-6),
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a touch fires selectionClick on the way down',
        (WidgetTester tester) async {
      final HapticRecorder haptics = HapticRecorder();
      haptics.install(tester);
      await _pumpPhone(tester, _app());
      haptics.clear();

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(SignaturePlateCard).first));
      // Past the tap recognizer's deadline: inside a scrollable the arena has
      // to resolve before onTapDown fires.
      await tester.pump(const Duration(milliseconds: 250));

      expect(haptics.selectionClicks, 1,
          reason: 'the tick must land while the finger is still down',);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('committing a choice is a heavier cue than the press',
        (WidgetTester tester) async {
      final HapticRecorder haptics = HapticRecorder();
      haptics.install(tester);
      await _pumpPhone(tester, _app(track: OrderTrack.architect));
      haptics.clear();

      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));

      // Two distinct cues, correctly layered: the press ticks, the commit
      // thumps. Collapsing them into one buzz is how a control stops feeling
      // like it responded.
      expect(haptics.selectionClicks, greaterThanOrEqualTo(1));
      expect(haptics.lightImpacts, greaterThanOrEqualTo(1));
    });

    testWidgets('completing the plate fires the medium impact exactly once',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      final HapticRecorder haptics = HapticRecorder();
      haptics.install(tester);

      await _pumpPhone(tester, _app(controller: controller));
      haptics.clear();

      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies);
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics.mediumImpacts, 1,
          reason: 'the balance lock is one moment, not three',);
    });

    testWidgets('haptics can be switched off wholesale',
        (WidgetTester tester) async {
      final HapticRecorder haptics = HapticRecorder();
      haptics.install(tester);
      MawzoonHaptics.enabled = false;
      addTearDown(() => MawzoonHaptics.enabled = true);

      await _pumpPhone(tester, _app());
      haptics.clear();
      await tester.tap(find.byType(SignaturePlateCard).first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics.calls, isEmpty);
    });
  });

  group('track one — curated', () {
    testWidgets('one tap loads a complete, checkout-ready plate',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(tester, _app(controller: controller));

      expect(controller.value, isA<PlateEmpty>());
      await tester.tap(find.byType(SignaturePlateCard).first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.value, isA<PlateBalanced>());
      expect(controller.canCheckout, isTrue);
      expect(controller.selection.protein,
          SignaturePlateCatalog.all.first.protein,);
    });

    testWidgets('the cards restate themselves at the athletic load',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(tester, _app(controller: controller));

      String firstCardFigures() {
        final Finder figures = find.descendant(
          of: find.byType(SignaturePlateCard).first,
          matching: find.byType(Text),
        );
        return figures
            .evaluate()
            .map((Element e) => (e.widget as Text).data ?? '')
            .join('|');
      }

      final String standard = firstCardFigures();
      controller.setScale(PortionScale.athleticLoad);
      await tester.pump(const Duration(milliseconds: 400));

      expect(firstCardFigures(), isNot(standard),
          reason: 'a volume switch that leaves six stale numbers behind is '
              'worse than no switch',);
    });

    testWidgets('the row carries every plate, building them lazily',
        (WidgetTester tester) async {
      await _pumpPhone(tester, _app());

      // The carousel builds only what is on screen, which is the point of a
      // carousel; assert the row's contents rather than its built children.
      final CuratedTrack row = tester.widget<CuratedTrack>(
        find.byType(CuratedTrack),
      );
      expect(row.plates, SignaturePlateCatalog.all);
      expect(find.byType(SignaturePlateCard), findsWidgets);

      // And the far end is genuinely reachable by scrolling to it.
      // pumpAndSettle is unusable on this screen: the plate's ambient layer
      // breathes on a 16-second loop by design, so frames never stop.
      await tester.scrollUntilVisible(
        find.text(SignaturePlateCatalog.all.last.name.ar),
        220,
        scrollable: find.descendant(
          of: find.byType(CuratedTrack),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.text(SignaturePlateCatalog.all.last.name.ar),
        findsOneWidget,
      );
    });
  });

  group('track two — the architect', () {
    testWidgets('opens on the protein step', (WidgetTester tester) async {
      await _pumpPhone(tester, _app(track: OrderTrack.architect));
      final Iterable<IngredientChip> chips = tester
          .widgetList<IngredientChip>(find.byType(IngredientChip));
      expect(chips, isNotEmpty);
      for (final IngredientChip chip in chips) {
        expect(chip.option.segment, PlateSegment.protein);
      }
    });

    testWidgets('advances by itself after each pick',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(
        tester,
        _app(controller: controller, track: OrderTrack.architect),
      );

      // Protein -> carb -> fibre, three taps and no navigation between them.
      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.selection.protein, isNotNull);
      expect(
        tester
            .widgetList<IngredientChip>(find.byType(IngredientChip))
            .every((IngredientChip c) => c.option.segment == PlateSegment.smartCarb),
        isTrue,
        reason: 'picking a protein should open the carb step by itself',
      );

      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.selection.carb, isNotNull);
      expect(
        tester
            .widgetList<IngredientChip>(find.byType(IngredientChip))
            .every((IngredientChip c) => c.option.segment == PlateSegment.vitalFiber),
        isTrue,
        reason: 'picking a carb should open the greens step by itself',
      );

      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.canCheckout, isTrue);
    });

    testWidgets('a step can be revisited without undoing the others',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(
        tester,
        _app(controller: controller, track: OrderTrack.architect),
      );

      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));

      // Jump back to protein via its step pill.
      final Finder proteinPill = find.byWidgetPredicate(
        (Widget w) =>
            w is TactileFeedbackWell &&
            (w.semanticLabel ?? '')
                .startsWith(PlateSegment.protein.label.ar),
      );
      expect(proteinPill, findsOneWidget);
      await tester.tap(proteinPill);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester
            .widgetList<IngredientChip>(find.byType(IngredientChip))
            .every((IngredientChip c) => c.option.segment == PlateSegment.protein),
        isTrue,
      );
      expect(controller.selection.carb, isNotNull,
          reason: 'going back must not undo the later choice',);
    });

    testWidgets('tapping the chosen component clears its compartment',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      controller.select(MawzoonCatalog.proteins.first);
      await _pumpPhone(
        tester,
        _app(controller: controller, track: OrderTrack.architect),
      );

      final Finder proteinPill = find.byWidgetPredicate(
        (Widget w) =>
            w is TactileFeedbackWell &&
            (w.semanticLabel ?? '')
                .startsWith(PlateSegment.protein.label.ar),
      );
      await tester.tap(proteinPill);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(IngredientChip).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.selection.protein, isNull);
    });
  });

  group('the two tracks share one plate', () {
    testWidgets('switching tracks keeps the plate exactly as it was',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(tester, _app(controller: controller));

      await tester.tap(find.byType(SignaturePlateCard).first);
      await tester.pump(const Duration(milliseconds: 400));
      final int before = controller.macros.displayKilocalories;

      await tester.tap(find.text('ابنِ طبقك'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PlateArchitectTrack), findsOneWidget);
      expect(controller.macros.displayKilocalories, before,
          reason: 'the plate is what is being built either way',);
    });

    testWidgets('a curated plate can be customised without starting over',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(tester, _app(controller: controller));

      await tester.tap(find.byType(SignaturePlateCard).first);
      await tester.pump(const Duration(milliseconds: 400));
      final String? carbBefore = controller.selection.carb?.id;

      await tester.tap(find.text('ابنِ طبقك'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.selection.carb?.id, carbBefore);
      expect(controller.canCheckout, isTrue,
          reason: 'handing a finished plate to the architect must not break it',);
    });

    testWidgets('the volume switch is shared, not duplicated per track',
        (WidgetTester tester) async {
      for (final OrderTrack track in OrderTrack.values) {
        await _pumpPhone(tester, _app(track: track));
        expect(find.byType(VolumeToggle), findsOneWidget,
            reason: 'two copies of the switch could disagree',);
      }
    });
  });

  group('checkout readiness', () {
    testWidgets('the action is inert until the plate is complete',
        (WidgetTester tester) async {
      final PlateBuilderController controller = PlateBuilderController();
      addTearDown(controller.dispose);
      await _pumpPhone(
        tester,
        _app(controller: controller, track: OrderTrack.architect),
      );

      Finder action() => find.byWidgetPredicate(
            (Widget w) => w is TactileFeedbackWell && w.semanticLabel == 'أكمل الأقسام',
          );
      expect(action(), findsOneWidget);
      expect(tester.widget<TactileFeedbackWell>(action()).enabled, isFalse);

      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies);
      await tester.pump(const Duration(milliseconds: 400));

      final Finder ready = find.byWidgetPredicate(
        (Widget w) => w is TactileFeedbackWell && w.semanticLabel == 'إتمام الطلب',
      );
      expect(ready, findsOneWidget);
      expect(tester.widget<TactileFeedbackWell>(ready).enabled, isTrue);
    });
  });

  group('bilingual', () {
    testWidgets('renders in English LTR without overflowing',
        (WidgetTester tester) async {
      await _pumpPhone(tester, _app(language: AppLanguage.english));
      expect(tester.takeException(), isNull);
      expect(find.text("Chef's plates"), findsOneWidget);
    });

    testWidgets('renders the architect in English too',
        (WidgetTester tester) async {
      await _pumpPhone(
        tester,
        _app(language: AppLanguage.english, track: OrderTrack.architect),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a small phone', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });
}
