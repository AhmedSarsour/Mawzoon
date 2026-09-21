@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/nutritional_summary.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/ui_primitives/plate/tri_partition_plate.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// Renders the plate at a few states so the geometry can be inspected as
/// pixels rather than trusted from arithmetic.
///
/// Regenerate with `flutter test --update-goldens --tags golden`. The test
/// font renders every glyph as a box, so these goldens are about the dish, the
/// compartment split and the ring — not about type.
NutritionalSummary _summary(List<IngredientOption> options) =>
    NutritionalSummary.fromComponents(
      scale: PortionScale.standardBalance,
      components: options
          .map((IngredientOption o) => o.atScale(PortionScale.standardBalance)),
    );

Widget _frame(NutritionalSummary summary, ThemeData theme, TextDirection dir) =>
    MaterialApp(
      theme: theme,
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 360,
                child: TriPartitionPlate(
                  summary: summary,
                  showAmbientWarmth: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  final ThemeData dark = AppTheme.dark(fonts: const BundledMawzoonFonts());
  final ThemeData light = AppTheme.light(fonts: const BundledMawzoonFonts());

  final NutritionalSummary empty =
      NutritionalSummary.empty(PortionScale.standardBalance);
  final NutritionalSummary partial = _summary(<IngredientOption>[
    MawzoonCatalog.smokedEntrecote,
  ]);
  final NutritionalSummary two = _summary(<IngredientOption>[
    MawzoonCatalog.smokedEntrecote,
    MawzoonCatalog.wholeBulgur,
  ]);
  final NutritionalSummary full = _summary(<IngredientOption>[
    MawzoonCatalog.herbGrilledBreast,
    MawzoonCatalog.airFriedSpicedPotatoes,
    MawzoonCatalog.charredGardenVeggies,
  ]);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    NutritionalSummary summary, {
    ThemeData? theme,
    TextDirection dir = TextDirection.rtl,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 260));
    await tester.pumpWidget(_frame(summary, theme ?? dark, dir));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('empty', (WidgetTester t) async => shoot(t, 'plate_empty', empty));
  testWidgets('one filled',
      (WidgetTester t) async => shoot(t, 'plate_one', partial),);
  testWidgets('two filled', (WidgetTester t) async => shoot(t, 'plate_two', two));
  testWidgets('complete', (WidgetTester t) async => shoot(t, 'plate_full', full));
  testWidgets('complete, light', (WidgetTester t) async =>
      shoot(t, 'plate_full_light', full, theme: light),);
  testWidgets('complete, ltr', (WidgetTester t) async =>
      shoot(t, 'plate_full_ltr', full, dir: TextDirection.ltr),);
}
