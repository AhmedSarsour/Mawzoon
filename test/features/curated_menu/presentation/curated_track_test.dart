import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';
import 'package:mawzoon/features/curated_menu/domain/signature_plate.dart';
import 'package:mawzoon/features/curated_menu/presentation/curated_track.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

Widget _host(
  Widget child, {
  double textScale = 1.0,
  TextDirection direction = TextDirection.rtl,
}) =>
    MaterialApp(
      theme: AppTheme.light(fonts: _fonts),
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  group('SignaturePlateCard layout', () {
    testWidgets('fits at the base text scale without overflow',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: CuratedTrack.cardWidth,
            height: CuratedTrack.rowHeight,
            child: SignaturePlateCard(
              plate: SignaturePlateCatalog.emberStandard,
              scale: PortionScale.standardBalance,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Edge case 3 in the plan: text scale must degrade (fewer tagline
    // lines, via `ellipsis`) rather than throw a RenderFlex overflow.
    testWidgets('degrades gracefully at 2.0x text scale',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: CuratedTrack.cardWidth,
            height: CuratedTrack.rowHeight,
            child: SignaturePlateCard(
              plate: SignaturePlateCatalog.emberStandard,
              scale: PortionScale.standardBalance,
              onPressed: () {},
            ),
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // K4: the widest card the carousel will ever render, at the worst text
    // scale, must still fit the row — 4:3 photo plus three text lines.
    for (final double textScale in <double>[1.0, 2.0]) {
      testWidgets(
          'tall card at max width fits rowHeight at ${textScale}x text',
          (WidgetTester tester) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: CuratedTrack.maxCardWidth,
              height: CuratedTrack.rowHeight,
              child: SignaturePlateCard(
                plate: SignaturePlateCatalog.emberStandard,
                scale: PortionScale.standardBalance,
                onPressed: () {},
              ),
            ),
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // A2 / edge case 5: a wrong path degrades to the placeholder, and the
    // guest never sees a broken-image icon or an error.
    testWidgets('a missing photo file shows the placeholder, not an error',
        (WidgetTester tester) async {
      const SignaturePlate ghost = SignaturePlate(
        id: 'signature.ghost',
        name: LocalizedText(ar: 'طبق', en: 'Plate'),
        tagline: LocalizedText(ar: 'وصف', en: 'Tagline'),
        chefNote: LocalizedText(ar: 'ملاحظة', en: 'Note'),
        protein: MawzoonCatalog.herbGrilledBreast,
        carb: MawzoonCatalog.steamedBasmati,
        fiber: MawzoonCatalog.charredGardenVeggies,
        basePriceMinorUnits: 4900,
        imageAsset: 'assets/food/plates/does_not_exist.webp',
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: CuratedTrack.cardWidth,
              height: CuratedTrack.rowHeight,
              child: SignaturePlateCard(
                plate: ghost,
                scale: PortionScale.standardBalance,
                onPressed: () {},
              ),
            ),
          ),
        );
        // Asset resolution is real I/O: extra pumps alone don't wait for it.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The placeholder is the warm radial-gradient box. Asserting it is
      // there (not just that nothing threw) is what makes this fail when the
      // errorBuilder is removed.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient is RadialGradient,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'a plate with no photo of its own composes its three component photos',
        (WidgetTester tester) async {
      expect(SignaturePlateCatalog.emberStandard.imageAsset, isNull);
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: CuratedTrack.cardWidth,
            height: CuratedTrack.rowHeight,
            child: SignaturePlateCard(
              plate: SignaturePlateCatalog.emberStandard,
              scale: PortionScale.standardBalance,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Breast, potatoes and charred veg all have cut-outs.
      expect(find.byType(Image), findsNWidgets(3));
    });
  });

  // K5: exactly one plate carries a badge, and it is the house default.
  group('badge', () {
    test('only emberStandard has one', () {
      final Iterable<String> badged = SignaturePlateCatalog.all
          .where((p) => p.badge != null)
          .map((p) => p.id);
      expect(badged, <String>[SignaturePlateCatalog.emberStandard.id]);
    });

    testWidgets('renders the badge text on the card that has it',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: CuratedTrack.cardWidth,
            height: CuratedTrack.rowHeight,
            child: SignaturePlateCard(
              plate: SignaturePlateCatalog.emberStandard,
              scale: PortionScale.standardBalance,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('مميز'), findsOneWidget);
    });

    testWidgets('renders no badge on a plate without one',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: CuratedTrack.cardWidth,
            height: CuratedTrack.rowHeight,
            child: SignaturePlateCard(
              plate: SignaturePlateCatalog.smokehouseBulgur,
              scale: PortionScale.standardBalance,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('مميز'), findsNothing);
    });
  });

  // K4 amendment: the centred card is the chosen plate. Swiping and tapping a
  // peeking card are the same act, and both must reach `onPlateChosen`.
  group('carousel', () {
    Future<List<String>> pump(WidgetTester tester) async {
      final List<String> chosen = <String>[];
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          CuratedTrack(
            scale: PortionScale.standardBalance,
            selectedPlateId: SignaturePlateCatalog.all.first.id,
            onPlateChosen: (p) => chosen.add(p.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('swiping to the next card chooses it',
        (WidgetTester tester) async {
      final List<String> chosen = await pump(tester);
      // RTL: the next card is reached by dragging to the right.
      await tester.drag(find.byType(PageView), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(chosen, <String>[SignaturePlateCatalog.all[1].id]);
    });

    testWidgets('tapping the centred card chooses it, once',
        (WidgetTester tester) async {
      final List<String> chosen = await pump(tester);
      await tester.tap(find.byType(SignaturePlateCard).first);
      await tester.pumpAndSettle();
      expect(chosen, <String>[SignaturePlateCatalog.all.first.id]);
    });

    testWidgets('tapping a peeking card centres and chooses it',
        (WidgetTester tester) async {
      final List<String> chosen = await pump(tester);
      // Only a sliver of the next card is on screen: tap that, as a thumb
      // would, rather than the card's (off-screen) centre.
      await tester.tapAt(const Offset(20, 422));
      await tester.pumpAndSettle();
      expect(chosen, <String>[SignaturePlateCatalog.all[1].id]);
    });

    testWidgets('the centred card is drawn larger than its neighbours',
        (WidgetTester tester) async {
      await pump(tester);
      // On-screen width: `getSize` ignores the scale transform, corners don't.
      double width(int i) {
        final Finder card = find.byType(SignaturePlateCard).at(i);
        return tester.getBottomRight(card).dx - tester.getTopLeft(card).dx;
      }

      expect(width(0), greaterThan(width(1)));
    });
  });
}
