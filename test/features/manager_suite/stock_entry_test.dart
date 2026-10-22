import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/arabic_count.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/features/manager_suite/application/manager_suite_controller.dart';
import 'package:mawzoon/features/manager_suite/domain/inventory_ledger.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/manager_suite/domain/stock_entry.dart';
import 'package:mawzoon/features/manager_suite/presentation/inventory_screen.dart';
import 'package:mawzoon/features/manager_suite/presentation/stock_count_screen.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

Finder _button(String label) => find.byWidgetPredicate(
      (Widget w) => w is TactileFeedbackWell && w.semanticLabel == label,
    );

Finder _fieldFor(RawIngredient i) => find.descendant(
      of: find.byKey(ValueKey<String>('count.${i.id}')),
      matching: find.byType(TextField),
    );

void main() {
  group('parseBulkAmount', () {
    test('reads the store-room unit, from either keyboard', () {
      final Quantity expected = Quantity.kilograms(12.4);
      expect(parseBulkAmount('12.4', MeasureUnit.gram), expected);
      expect(parseBulkAmount('١٢٫٤', MeasureUnit.gram), expected);
      expect(parseBulkAmount('12,4', MeasureUnit.gram), expected);
      expect(parseBulkAmount(' 12.4 ', MeasureUnit.gram), expected);
      expect(parseBulkAmount('8', MeasureUnit.millilitre), Quantity.litres(8));
      expect(parseBulkAmount('30', MeasureUnit.piece), Quantity.pieces(30));
    });

    test('refuses what is not an amount', () {
      for (final String typed in <String>['', 'abc', '1.2.3', '-3', '.']) {
        expect(parseBulkAmount(typed, MeasureUnit.gram), isNull, reason: typed);
      }
    });

    test('a movement lands where the manager expects', () {
      final Quantity onHand = Quantity.kilograms(12.4);
      final Quantity five = Quantity.kilograms(5);
      expect(applyMovement(onHand, StockMovement.count, five), five);
      expect(
        applyMovement(onHand, StockMovement.delivery, five),
        Quantity.kilograms(17.4),
      );
      expect(
        applyMovement(onHand, StockMovement.writeOff, five),
        Quantity.kilograms(7.4),
      );
    });
  });

  test('items agree with their count', () {
    expect(arabicItemsGenitive(1), 'مادة واحدة');
    expect(arabicItemsGenitive(2), 'مادتين');
    expect(arabicItemsGenitive(8), '8 مواد');
    expect(arabicItemsGenitive(11), '11 مادة');
    expect(arabicItemsGenitive(23), '23 مادة');
    expect(arabicItemsGenitive(103), '103 مواد');
    expect(
      arabicKilocalories(550),
      '550 سعرة',
      reason: 'unchanged by the extraction',
    );
  });

  group('screens', () {
    late ManagerSuiteController suite;

    Future<void> pumpInventory(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      suite = ManagerSuiteController(ledger: InventoryLedger());
      addTearDown(suite.dispose);
      suite.setCount(RawStore.chickenBreast, Quantity.kilograms(12.4));
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(fonts: _fonts),
          locale: const Locale('ar'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Scaffold(body: InventoryScreen(controller: suite)),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('count mode saves only what was counted, in one press',
        (WidgetTester t) async {
      await pumpInventory(t);
      await t.tap(_button('ابدأ الجرد'));
      await t.pumpAndSettle();
      expect(find.byType(StockCountScreen), findsOneWidget);
      expect(
        t.widget<TactileFeedbackWell>(_button('احفظ الجرد')).enabled,
        isFalse,
      );

      await t.enterText(_fieldFor(RawStore.chickenBreast), '9');
      await t.enterText(_fieldFor(RawStore.oliveOil), '٨');
      await t.pump();
      expect(_button('احفظ جرد مادتين'), findsOneWidget);

      await t.tap(_button('احفظ جرد مادتين'));
      await t.pumpAndSettle();
      expect(find.byType(StockCountScreen), findsNothing);
      expect(
        suite.ledger.onHand(RawStore.chickenBreast),
        Quantity.kilograms(9),
      );
      expect(suite.ledger.onHand(RawStore.oliveOil), Quantity.litres(8));
      expect(
        suite.ledger.onHand(RawStore.lemon).isZero,
        isTrue,
        reason: 'a blank field leaves the book alone',
      );
    });

    testWidgets('a field that does not parse blocks the save',
        (WidgetTester t) async {
      await pumpInventory(t);
      await t.tap(_button('ابدأ الجرد'));
      await t.pumpAndSettle();
      await t.enterText(_fieldFor(RawStore.chickenBreast), '1.2.3');
      await t.pump();
      expect(
        t.widget<TactileFeedbackWell>(_button('احفظ جرد مادة واحدة')).enabled,
        isFalse,
      );
    });

    testWidgets('a delivery shows before → after, then adds',
        (WidgetTester t) async {
      await pumpInventory(t);
      await t.tap(
        find.bySemanticsLabel(RegExp('^${RawStore.chickenBreast.name.ar},')),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<TactileFeedbackWell>(_button('سجّل الاستلام')).enabled,
        isFalse,
      );

      await t.enterText(find.byType(TextField), '15');
      await t.pump();
      expect(find.text('27.40 كجم'), findsOneWidget);

      await t.tap(_button('سجّل الاستلام'));
      await t.pumpAndSettle();
      expect(
        suite.ledger.onHand(RawStore.chickenBreast),
        Quantity.kilograms(27.4),
      );
    });

    testWidgets('a write-off takes away', (WidgetTester t) async {
      await pumpInventory(t);
      await t.tap(
        find.bySemanticsLabel(RegExp('^${RawStore.chickenBreast.name.ar},')),
      );
      await t.pumpAndSettle();
      await t.tap(_button('هدر'));
      await t.pump();
      await t.enterText(find.byType(TextField), '0.4');
      await t.pump();
      await t.tap(_button('سجّل الهدر'));
      await t.pumpAndSettle();
      expect(
        suite.ledger.onHand(RawStore.chickenBreast),
        Quantity.kilograms(12),
      );
    });

    testWidgets(
      'golden: count mode',
      (WidgetTester t) async {
        await pumpInventory(t);
        await t.tap(_button('ابدأ الجرد'));
        await t.pumpAndSettle();
        await t.enterText(_fieldFor(RawStore.chickenBreast), '12.4');
        await t.enterText(_fieldFor(RawStore.oliveOil), '8');
        await t.pump(const Duration(milliseconds: 400));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/stock_count_mode.png'),
        );
      },
      tags: <String>['golden'],
    );

    testWidgets(
      'golden: delivery dialog',
      (WidgetTester t) async {
        await pumpInventory(t);
        await t.tap(
          find.bySemanticsLabel(RegExp('^${RawStore.chickenBreast.name.ar},')),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '15');
        await t.pump(const Duration(milliseconds: 400));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/stock_delivery_dialog.png'),
        );
      },
      tags: <String>['golden'],
    );
  });
}
