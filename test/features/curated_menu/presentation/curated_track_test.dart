import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';
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

    testWidgets(
        'a catalogue plate (none has imageAsset yet) draws no Image widget',
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
      expect(find.byType(Image), findsNothing);
    });
  });
}
