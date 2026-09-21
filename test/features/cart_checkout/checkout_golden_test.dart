@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/features/cart_checkout/presentation/checkout_sheet.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// Renders the checkout sheet so its ergonomics can be inspected as pixels.
void main() {
  const BundledMawzoonFonts fonts = BundledMawzoonFonts();

  final PlateSelection plate = PlateSelection.empty
      .select(MawzoonCatalog.smokedEntrecote)
      .select(MawzoonCatalog.wholeBulgur)
      .select(MawzoonCatalog.mediterraneanSumacSalad);

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    AppLanguage language = AppLanguage.arabic,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(brightness, language: language, fonts: fonts),
        locale: Locale(language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CheckoutSheet(selection: plate),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('sheet, dark', (WidgetTester t) async {
    await shoot(t, 'checkout_dark', brightness: Brightness.dark);
  });

  testWidgets('sheet, light', (WidgetTester t) async {
    await shoot(t, 'checkout_light', brightness: Brightness.light);
  });

  testWidgets('sheet, english', (WidgetTester t) async {
    await shoot(t, 'checkout_en',
        brightness: Brightness.dark, language: AppLanguage.english,);
  });
}
