@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/ui_primitives/menu/menu_scope.dart';
import 'package:mawzoon/core/menu/recipe_calibration.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/manager_suite/application/manager_suite_controller.dart';
import 'package:mawzoon/features/manager_suite/domain/inventory_ledger.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/manager_suite/presentation/manager_shell.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/features/plate_builder/presentation/plate_architect_track.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// Renders the back office, and the one guest-facing consequence of it, so
/// both can be looked at rather than only asserted about.
///
/// The service below is mid-evening on purpose: one dish taken off by hand,
/// one below the safety buffer because an ingredient ran down, one running low
/// but still selling, and one component carrying a measurement of its own.
void main() {
  const BundledMawzoonFonts fonts = BundledMawzoonFonts();
  final DateTime when = DateTime.utc(2026, 5, 2, 19, 40);

  ManagerSuiteController midService() {
    final ManagerSuiteController manager = ManagerSuiteController(
      ledger: InventoryLedger.stockedFor(30),
      now: () => when,
      signedInAs: 'lina',
    );

    // A batch of chicken that ran lean, measured and entered.
    manager.calibrate(
      CalibrationDraft.from(MawzoonCatalog.herbGrilledBreast).copyWith(
        proteinGrams:
            MawzoonCatalog.herbGrilledBreast.baseMacros.proteinGrams + 2.5,
        fatGrams: MawzoonCatalog.herbGrilledBreast.baseMacros.fatGrams - 1,
        note: 'batch 214',
      ),
      published: MawzoonCatalog.herbGrilledBreast,
    );

    // The fryer is down: chips off by hand.
    manager.setForcedOff(MawzoonCatalog.airFriedSpicedPotatoes.id, off: true);

    // Parsley nearly gone, which takes the salad and the kofta with it.
    manager.setCount(RawStore.parsley, Quantity.grams(38));

    // A steady evening on the basmati.
    const OrderDraft order = OrderDraft(
      selection: PlateSelection(
        protein: MawzoonCatalog.marinatedThighs,
        carb: MawzoonCatalog.steamedBasmati,
        fiber: MawzoonCatalog.charredGardenVeggies,
      ),
      mode: FulfilmentMode.pickup,
      payment: PaymentMethod.cash,
    );
    for (int i = 0; i < 20; i++) {
      manager.recordPlacedOrder(order, orderCode: 'M-$i');
    }

    return manager;
  }

  Widget app({
    required Widget home,
    required Brightness brightness,
    AppLanguage language = AppLanguage.arabic,
  }) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(brightness, language: language, fonts: fonts),
        locale: Locale(language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: home,
      );

  Future<void> shootShell(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    AppLanguage language = AppLanguage.arabic,
    ManagerTab tab = ManagerTab.inventory,
    Size size = const Size(1280, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ManagerSuiteController manager = midService();
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      app(
        brightness: brightness,
        language: language,
        home: ManagerShell(controller: manager, initialTab: tab),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('inventory, dark', (WidgetTester t) async {
    await shootShell(t, 'manager_inventory_dark', brightness: Brightness.dark);
  });

  testWidgets('inventory, light', (WidgetTester t) async {
    await shootShell(
      t,
      'manager_inventory_light',
      brightness: Brightness.light,
    );
  });

  testWidgets('inventory, english', (WidgetTester t) async {
    await shootShell(
      t,
      'manager_inventory_en',
      brightness: Brightness.dark,
      language: AppLanguage.english,
    );
  });

  testWidgets('calibrator, dark', (WidgetTester t) async {
    await shootShell(
      t,
      'manager_calibrator_dark',
      brightness: Brightness.dark,
      tab: ManagerTab.recipes,
    );
  });

  testWidgets('back office on a laptop-narrow window', (WidgetTester t) async {
    await shootShell(
      t,
      'manager_inventory_narrow',
      brightness: Brightness.dark,
      size: const Size(720, 1000),
    );
  });

  testWidgets('the rail as a guest meets it', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final ManagerSuiteController manager = midService();
    addTearDown(manager.dispose);
    // Take two proteins off so the carousel shows both states side by side.
    manager
      ..setForcedOff(MawzoonCatalog.smokedEntrecote.id, off: true)
      ..setForcedOff(MawzoonCatalog.pulledSlowCookedBeef.id, off: true);

    await t.pumpWidget(
      app(
        brightness: Brightness.dark,
        home: MenuScope(
          book: manager.book,
          availability: manager.availability,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlateArchitectTrack(
                selection: PlateSelection.empty,
                onOptionChosen: (IngredientOption _) {},
                onOptionCleared: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/menu_rail_guest.png'),
    );
  });
}
