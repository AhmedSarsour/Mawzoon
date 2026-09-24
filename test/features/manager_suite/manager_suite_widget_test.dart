import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/ui_primitives/menu/menu_scope.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/menu/recipe_book.dart';
import 'package:mawzoon/core/menu/recipe_calibration.dart';
import 'package:mawzoon/core/menu/stock_status.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/manager_suite/application/manager_suite_controller.dart';
import 'package:mawzoon/features/manager_suite/domain/inventory_ledger.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/manager_suite/presentation/manager_shell.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/features/plate_builder/presentation/plate_architect_track.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

void main() {
  const ProteinOption chicken = MawzoonCatalog.herbGrilledBreast;
  final DateTime when = DateTime.utc(2026, 5, 2, 15);

  Widget host(
    Widget child, {
    AppLanguage language = AppLanguage.arabic,
    RecipeBook book = RecipeBook.published,
    MenuAvailability availability = MenuAvailability.everything,
    Brightness brightness = Brightness.dark,
  }) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(
          brightness,
          language: language,
          fonts: const BundledMawzoonFonts(),
        ),
        locale: Locale(language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: MenuScope(
          book: book,
          availability: availability,
          child: Scaffold(body: child),
        ),
      );

  // -------------------------------------------------------------------
  // The scope
  // -------------------------------------------------------------------

  group('menu scope', () {
    testWidgets('a widget with no scope above it sees the published menu',
        (WidgetTester tester) async {
      late MenuScope seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              seen = MenuScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen.book.isPublished, isTrue);
      expect(seen.availability, MenuAvailability.everything);
    });

    testWidgets('sold-out components stay in the list', (
      WidgetTester tester,
    ) async {
      late List<MenuEntry> entries;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) {
              entries = MenuScope.of(
                context,
              ).entriesFor(context, PlateSegment.protein);
              return const SizedBox.shrink();
            },
          ),
          availability: InventoryLedger().availability,
        ),
      );
      expect(entries, hasLength(MawzoonCatalog.proteins.length));
      expect(entries.every((MenuEntry e) => !e.isOrderable), isTrue);
    });
  });

  // -------------------------------------------------------------------
  // The rail as a guest meets it
  // -------------------------------------------------------------------

  group('the architect carousel', () {
    Widget track({
      RecipeBook book = RecipeBook.published,
      MenuAvailability availability = MenuAvailability.everything,
      required void Function(IngredientOption) onChosen,
    }) =>
        host(
          Align(
            alignment: Alignment.bottomCenter,
            child: PlateArchitectTrack(
              selection: PlateSelection.empty,
              onOptionChosen: onChosen,
              onOptionCleared: (_) {},
            ),
          ),
          book: book,
          availability: availability,
        );

    testWidgets('an available component can be chosen', (
      WidgetTester tester,
    ) async {
      final List<IngredientOption> chosen = <IngredientOption>[];
      await tester.pumpWidget(track(onChosen: chosen.add));
      await tester.pump();

      await tester.tap(find.text(chicken.name.ar));
      await tester.pump();
      expect(chosen.single.id, chicken.id);
    });

    testWidgets('a sold-out component is shown, and cannot be chosen', (
      WidgetTester tester,
    ) async {
      final List<IngredientOption> chosen = <IngredientOption>[];
      await tester.pumpWidget(
        track(
          onChosen: chosen.add,
          availability: InventoryLedger().availability,
        ),
      );
      await tester.pump();

      // Still on screen — a carousel that drops an item shuffles everything
      // the guest was reaching for.
      expect(find.text(chicken.name.ar), findsOneWidget);
      expect(
        find.text(SoldOutReason.belowSafetyBuffer.label.ar),
        findsWidgets,
      );

      await tester.tap(find.text(chicken.name.ar));
      await tester.pump();
      expect(chosen, isEmpty);
    });

    testWidgets('an unavailable chip is dimmed rather than struck out', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        track(
          onChosen: (_) {},
          availability: InventoryLedger().availability,
        ),
      );
      await tester.pump();

      final AnimatedOpacity dimmed = tester.widget<AnimatedOpacity>(
        find
            .descendant(
              of: find.byType(IngredientChip),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(dimmed.opacity, lessThan(1.0));
      expect(dimmed.opacity, greaterThan(0.2), reason: 'legible, not hidden');
    });

    testWidgets('a sold-out chip says so to a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        track(
          onChosen: (_) {},
          availability: InventoryLedger().availability,
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(SoldOutReason.belowSafetyBuffer.label.ar)),
        ),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('a recalibration reaches the carousel figures', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(track(onChosen: (_) {}));
      await tester.pump();
      final String published = '${chicken.baseKilocalories.round()} kcal · '
          '${chicken.basePortionGrams.round()}g';
      expect(find.text(published), findsOneWidget);

      await tester.pumpWidget(
        track(
          onChosen: (_) {},
          book: RecipeBook.published.withCalibration(
            CalibrationDraft.from(chicken)
                .copyWith(fatGrams: chicken.baseMacros.fatGrams + 10)
                .commit(published: chicken, by: 'lina', at: when),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(published), findsNothing);
      expect(
        find.text(
          '${(chicken.baseKilocalories + 90).round()} kcal · '
          '${chicken.basePortionGrams.round()}g',
        ),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------
  // The back office
  // -------------------------------------------------------------------

  group('manager shell', () {
    ManagerSuiteController suite({int portions = 60}) => ManagerSuiteController(
          ledger: InventoryLedger.stockedFor(portions),
          now: () => when,
          signedInAs: 'lina',
        );

    Future<ManagerSuiteController> pumpShell(
      WidgetTester tester, {
      AppLanguage language = AppLanguage.arabic,
      ManagerTab? tab,
      int portions = 60,
      Brightness brightness = Brightness.dark,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ManagerSuiteController manager = suite(portions: portions);
      addTearDown(manager.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.of(
            brightness,
            language: language,
            fonts: const BundledMawzoonFonts(),
          ),
          locale: Locale(language.code),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: ManagerShell(controller: manager, initialTab: tab),
        ),
      );
      await tester.pump();
      return manager;
    }

    testWidgets('it opens on inventory, not on the recipes', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('ما يمكن بيعه'), findsOneWidget);
      expect(find.text('المخزون'), findsWidgets);
    });

    testWidgets('the store panel reads in the ingredient\'s own unit', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, language: AppLanguage.english);
      // Olive oil is poured, potato is weighed. A back office that shows both
      // in grams has already lost the plot. At a full store both read in bulk.
      expect(find.textContaining(RegExp(r'\b(L|ml)\b')), findsWidgets);
      expect(find.textContaining(RegExp(r'\b(kg|g)\b')), findsWidgets);
    });

    testWidgets('the units are localised, not transliterated', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(
        find.textContaining(MeasureUnit.gram.bulk.ar),
        findsWidgets,
        reason: 'kilograms should read كجم on an Arabic board',
      );
      expect(
        find.textContaining(MeasureUnit.millilitre.bulk.ar),
        findsWidgets,
      );
    });

    testWidgets('a manager can take a dish off and put it back', (
      WidgetTester tester,
    ) async {
      final ManagerSuiteController manager = await pumpShell(tester);
      final String basmati = MawzoonCatalog.steamedBasmati.id;
      expect(manager.availability.canOrder(basmati), isTrue);

      await tester.tap(
        find.bySemanticsLabel(
          '${MawzoonCatalog.steamedBasmati.name.ar}, take off',
        ),
      );
      await tester.pump();
      expect(manager.availability.canOrder(basmati), isFalse);

      await tester.tap(
        find.bySemanticsLabel(
          '${MawzoonCatalog.steamedBasmati.name.ar}, put back on',
        ),
      );
      await tester.pump();
      expect(manager.availability.canOrder(basmati), isTrue);
    });

    testWidgets('the calibrator saves a measurement and stamps it', (
      WidgetTester tester,
    ) async {
      final ManagerSuiteController manager = await pumpShell(
        tester,
        tab: ManagerTab.recipes,
      );

      // The first component is selected by default; nudge its protein twice.
      final IngredientOption first = MawzoonCatalog.all.first;
      final Finder up = find.bySemanticsLabel(
        '${CalibrationField.protein.label.ar} up',
      );
      await tester.tap(up);
      await tester.pump();
      await tester.tap(up);
      await tester.pump();

      await tester.tap(find.text('احفظ القياس'));
      await tester.pump();

      expect(manager.history, hasLength(1));
      expect(manager.history.single.componentId, first.id);
      expect(manager.history.single.by, 'lina');
      expect(
        manager.book.resolve(first).baseMacros.proteinGrams,
        first.baseMacros.proteinGrams + 1,
      );
    });

    testWidgets('saving is unreachable while a blocking finding stands', (
      WidgetTester tester,
    ) async {
      final ManagerSuiteController manager = await pumpShell(
        tester,
        tab: ManagerTab.recipes,
      );

      // Drive the fibre above the carbohydrate — the edit that would
      // otherwise reach MacroProfile's assert and take the app down.
      final Finder fibreUp = find.bySemanticsLabel(
        '${CalibrationField.fibre.label.ar} up',
      );
      for (int i = 0; i < 80; i++) {
        await tester.tap(fibreUp);
      }
      await tester.pump();

      final FilledButton save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'احفظ القياس'),
      );
      expect(save.onPressed, isNull);

      await tester.tap(find.text('احفظ القياس'));
      await tester.pump();
      expect(manager.history, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving is also unreachable when nothing has changed', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, tab: ManagerTab.recipes);
      final FilledButton save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'احفظ القياس'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('a step never falls below zero', (WidgetTester tester) async {
      await pumpShell(tester, tab: ManagerTab.recipes);
      final Finder down = find.bySemanticsLabel(
        '${CalibrationField.fibre.label.ar} down',
      );
      for (int i = 0; i < 40; i++) {
        await tester.tap(down);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('0g'), findsWidgets);
    });

    testWidgets('the back office reads in English too', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, language: AppLanguage.english);
      expect(find.text('What can be sold'), findsOneWidget);
      expect(find.text('On the shelf'), findsOneWidget);
    });

    testWidgets('a sold-out dish names what is holding it up', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ManagerSuiteController manager = ManagerSuiteController(
        ledger: InventoryLedger.stockedFor(60),
        now: () => when,
      );
      addTearDown(manager.dispose);
      // Empty the potato bin and nothing else.
      manager.setCount(RawStore.potato, RawStore.potato.none);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(
            Brightness.dark,
            language: AppLanguage.english,
            fonts: const BundledMawzoonFonts(),
          ),
          locale: const Locale('en'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: ManagerShell(controller: manager),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Potato'), findsWidgets);
      expect(
        find.textContaining(SoldOutReason.belowSafetyBuffer.note.en),
        findsWidgets,
      );
    });
  });

  // -------------------------------------------------------------------
  // Checkout
  // -------------------------------------------------------------------

  group('checkout', () {
    test('a plate holding a sold-out component cannot be placed', () {
      const OrderDraft draft = OrderDraft(
        selection: PlateSelection(
          protein: chicken,
          carb: MawzoonCatalog.steamedBasmati,
          fiber: MawzoonCatalog.charredGardenVeggies,
        ),
        mode: FulfilmentMode.pickup,
        payment: PaymentMethod.cash,
      );
      expect(draft.isPlaceable, isTrue);

      final InventoryLedger ledger = InventoryLedger.stockedFor(60);
      ledger.setForcedOff(MawzoonCatalog.steamedBasmati.id, off: true);

      expect(draft.isPlaceableIn(ledger.availability), isFalse);
      expect(
        draft.unavailableIn(ledger.availability).single.id,
        MawzoonCatalog.steamedBasmati.id,
      );
    });
  });
}
