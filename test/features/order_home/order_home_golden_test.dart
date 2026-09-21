@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/features/order_home/presentation/order_home_screen.dart';
import 'package:mawzoon/features/plate_builder/application/plate_builder_controller.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// Renders the dual-track screen so the layout can be inspected as pixels.
///
/// Regenerate with `flutter test --update-goldens --tags golden`. The test font
/// draws every glyph as a box, so these verify composition and the thumb-zone
/// split rather than type.
void main() {
  const BundledMawzoonFonts fonts = BundledMawzoonFonts();

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required OrderTrack track,
    required Brightness brightness,
    AppLanguage language = AppLanguage.arabic,
    void Function(PlateBuilderController)? seed,
  }) async {
    final PlateBuilderController controller = PlateBuilderController();
    addTearDown(controller.dispose);
    seed?.call(controller);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(brightness, language: language, fonts: fonts),
        locale: Locale(language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: OrderHomeScreen(controller: controller, initialTrack: track),
      ),
    );
    // Explicit pumps rather than pumpAndSettle: the plate's ambient layer
    // breathes forever by design, so frames never stop on this screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('curated, empty, dark', (WidgetTester t) async {
    await shoot(t, 'order_curated_dark',
        track: OrderTrack.curated, brightness: Brightness.dark,);
  });

  testWidgets('curated, loaded, light', (WidgetTester t) async {
    await shoot(
      t,
      'order_curated_light',
      track: OrderTrack.curated,
      brightness: Brightness.light,
      seed: (PlateBuilderController c) => c
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.airFriedSpicedPotatoes)
        ..select(MawzoonCatalog.charredGardenVeggies),
    );
  });

  testWidgets('architect, mid-build, dark', (WidgetTester t) async {
    await shoot(
      t,
      'order_architect_dark',
      track: OrderTrack.architect,
      brightness: Brightness.dark,
      seed: (PlateBuilderController c) => c.select(MawzoonCatalog.smokedEntrecote),
    );
  });

  testWidgets('architect, english, dark', (WidgetTester t) async {
    await shoot(t, 'order_architect_en',
        track: OrderTrack.architect,
        brightness: Brightness.dark,
        language: AppLanguage.english,);
  });
}
