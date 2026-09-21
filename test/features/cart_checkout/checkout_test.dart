import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/macro_targets.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/core/pricing/money.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/saved_places.dart';
import 'package:mawzoon/features/cart_checkout/presentation/checkout_sheet.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/ui_primitives/controls/macro_capsule.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

final PlateSelection _completePlate = PlateSelection.empty
    .select(MawzoonCatalog.herbGrilledBreast)
    .select(MawzoonCatalog.steamedBasmati)
    .select(MawzoonCatalog.charredGardenVeggies);

final PlateSelection _partialPlate =
    PlateSelection.empty.select(MawzoonCatalog.herbGrilledBreast);

void main() {
  group('pricing', () {
    test('adds up the lines it shows', () {
      final PriceBreakdown price = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.delivery,
      );

      expect(price.base, PriceBreakdown.basePlatePrice);
      expect(price.deliveryFee, PriceBreakdown.standardDeliveryFee);
      expect(price.loadUplift, Money.zero);
      expect(price.subtotal, price.base + price.deliveryFee);
      expect(price.total, price.subtotal + price.tax);
    });

    test('VAT is 15% of everything above it', () {
      final PriceBreakdown price = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
      );
      expect(price.tax, price.subtotal.percentage(PriceBreakdown.vatRate));
    });

    test('pickup carries no delivery fee', () {
      final PriceBreakdown pickup = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
      );
      expect(pickup.deliveryFee, Money.zero);
      expect(
        pickup.total,
        lessThan(
          PriceBreakdown.forPlate(
            selection: _completePlate,
            mode: FulfilmentMode.delivery,
          ).total,
        ),
      );
    });

    test('component surcharges reach the bill', () {
      final PlateSelection withEntrecote = PlateSelection.empty
          .select(MawzoonCatalog.smokedEntrecote)
          .select(MawzoonCatalog.steamedBasmati)
          .select(MawzoonCatalog.charredGardenVeggies);

      final PriceBreakdown price = PriceBreakdown.forPlate(
        selection: withEntrecote,
        mode: FulfilmentMode.pickup,
      );
      expect(
        price.componentSurcharges,
        Money(MawzoonCatalog.smokedEntrecote.surchargeMinorUnits),
      );
      expect(price.componentSurcharges.isZero, isFalse);
    });

    test('the athletic load carries a flat uplift', () {
      final PriceBreakdown standard = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
      );
      final PriceBreakdown athletic = PriceBreakdown.forPlate(
        selection: _completePlate.copyWith(scale: PortionScale.athleticLoad),
        mode: FulfilmentMode.pickup,
      );
      expect(athletic.loadUplift, PriceBreakdown.athleticLoadUplift);
      expect(standard.loadUplift, Money.zero);
      expect(athletic.total, greaterThan(standard.total));
    });

    // A row reading "Delivery 0.00" is noise pretending to be transparency.
    test('zero lines are left off the receipt', () {
      final List<LocalizedText> pickupLabels = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
      ).lines().map((line) => line.$1).toList();

      expect(
        pickupLabels.map((LocalizedText l) => l.en),
        isNot(contains('Delivery')),
      );
      expect(pickupLabels.map((LocalizedText l) => l.en), contains('VAT'));
    });
  });

  group('the draft knows what it is missing', () {
    test('an incomplete plate cannot be placed, and says so', () {
      final OrderDraft draft = OrderDraft(
        selection: _partialPlate,
        mode: FulfilmentMode.pickup,
        payment: PaymentMethod.wallet,
      );
      expect(draft.isPlaceable, isFalse);
      expect(draft.blocker!.en, contains('three compartments'));
    });

    test('delivery without an address cannot be placed, and says so', () {
      final OrderDraft draft = OrderDraft(
        selection: _completePlate,
        mode: FulfilmentMode.delivery,
        payment: PaymentMethod.wallet,
      );
      expect(draft.isPlaceable, isFalse);
      expect(draft.blocker!.en, contains('address'));
    });

    test('pickup needs no address', () {
      final OrderDraft draft = OrderDraft(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
        payment: PaymentMethod.cash,
      );
      expect(draft.isPlaceable, isTrue);
      expect(draft.blocker, isNull);
    });

    test('switching to pickup keeps the address for the way back', () {
      final OrderDraft delivery = OrderDraft(
        selection: _completePlate,
        mode: FulfilmentMode.delivery,
        payment: PaymentMethod.wallet,
        address: SavedPlaces.home,
      );
      final OrderDraft pickup = delivery.copyWith(mode: FulfilmentMode.pickup);
      expect(pickup.address, SavedPlaces.home,
          reason: 'changing your mind twice should not cost the address',);
    });

    test('lists its components in build order', () {
      final OrderDraft draft = OrderDraft(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
        payment: PaymentMethod.wallet,
      );
      expect(draft.components, hasLength(3));
      expect(draft.components.first, MawzoonCatalog.herbGrilledBreast);
      expect(draft.summary.isComplete, isTrue);
    });
  });

  group('saved places', () {
    test('exactly one address is the default', () {
      expect(
        SavedPlaces.all.where((DeliveryAddress a) => a.isDefault),
        hasLength(1),
      );
      expect(SavedPlaces.defaultAddress, SavedPlaces.home);
    });

    test('every address is recognisable by a label the guest chose', () {
      for (final DeliveryAddress address in SavedPlaces.all) {
        expect(address.label.ar.trim(), isNotEmpty);
        expect(address.label.en.trim(), isNotEmpty);
        expect(address.summary, contains(address.district));
      }
    });
  });

  group('the sheet is answerable the moment it opens', () {
    Future<void> open(WidgetTester tester, {PlateSelection? plate}) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(fonts: _fonts),
          locale: const Locale('ar'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Scaffold(
            body: CheckoutSheet(selection: plate ?? _completePlate),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('opens with an address and a payment method already chosen',
        (WidgetTester tester) async {
      await open(tester);

      // Two taps means the first one was the dock. Everything needed to place
      // the order is already answered when the sheet appears.
      expect(find.text(SavedPlaces.home.label.ar), findsOneWidget);
      expect(find.text(PaymentMethod.wallet.label.ar), findsOneWidget);

      final Finder confirm = find.byWidgetPredicate(
        (Widget w) => w is TactileFeedbackWell && w.semanticLabel == 'تأكيد الطلب',
      );
      expect(confirm, findsOneWidget);
      expect(tester.widget<TactileFeedbackWell>(confirm).enabled, isTrue,
          reason: 'the second tap must be live on arrival',);
    });

    testWidgets('one tap places the order and returns the draft',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      OrderDraft? placed;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(fonts: _fonts),
          locale: const Locale('ar'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    placed = await showCheckoutSheet(
                      context,
                      selection: _completePlate,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byWidgetPredicate(
          (Widget w) => w is TactileFeedbackWell && w.semanticLabel == 'تأكيد الطلب',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(placed, isNotNull);
      expect(placed!.isPlaceable, isTrue);
      expect(placed!.address, SavedPlaces.home);
      expect(placed!.payment, PaymentMethod.wallet);
    });

    testWidgets('switching to pickup drops the address picker and the fee',
        (WidgetTester tester) async {
      await open(tester);
      expect(find.text(SavedPlaces.gym.label.ar), findsOneWidget);

      await tester.tap(find.text(FulfilmentMode.pickup.label.ar));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(SavedPlaces.gym.label.ar), findsNothing,
          reason: 'an address picker on a pickup order is dead weight',);
      expect(find.text('التوصيل'), findsNothing);
    });

    testWidgets('the total restates itself when the mode changes',
        (WidgetTester tester) async {
      await open(tester);

      final Money deliveryTotal = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.delivery,
      ).total;
      final Money pickupTotal = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.pickup,
      ).total;
      expect(deliveryTotal, isNot(pickupTotal));

      expect(find.text(deliveryTotal.format(AppLanguage.arabic)), findsOneWidget);

      await tester.tap(find.text(FulfilmentMode.pickup.label.ar));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(pickupTotal.format(AppLanguage.arabic)), findsOneWidget);
      expect(find.text(deliveryTotal.format(AppLanguage.arabic)), findsNothing,
          reason: 'a stale total is worse than no total',);
    });

    testWidgets('an unfinished plate blocks, and the button says why',
        (WidgetTester tester) async {
      await open(tester, plate: _partialPlate);

      final Finder confirm = find.byWidgetPredicate(
        (Widget w) => w is TactileFeedbackWell && w.semanticLabel == 'تأكيد الطلب',
      );
      expect(tester.widget<TactileFeedbackWell>(confirm).enabled, isFalse);
      // Not a grey button sitting silent: it names the thing that is missing.
      expect(find.text('أكمل أقسام الطبق الثلاثة'), findsOneWidget);
    });

    testWidgets('no field asks for a card number',
        (WidgetTester tester) async {
      await open(tester);
      expect(find.byType(TextField), findsNothing,
          reason: 'a hungry person typing sixteen digits is a lost order',);
    });
  });

  group('the dock', () {
    Future<void> pumpDock(
      WidgetTester tester, {
      required PlateSelection plate,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(fonts: _fonts),
          locale: const Locale('ar'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MacroCapsule(
                summary: plate.summary,
                onScaleChanged: (_) {},
                onCheckout: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('shows protein against its target, not as a bare number',
        (WidgetTester tester) async {
      await pumpDock(tester, plate: _completePlate);
      final double grams = _completePlate.summary.totalMacros.proteinGrams;
      expect(
        find.text('${grams.round()} / '
            '${MacroTargets.standard.proteinGrams.round()} g'),
        findsOneWidget,
      );
      expect(find.byType(ProteinProgressBar), findsOneWidget);
    });

    testWidgets('the target moves with the portion',
        (WidgetTester tester) async {
      await pumpDock(
        tester,
        plate: _completePlate.copyWith(scale: PortionScale.athleticLoad),
      );
      expect(
        find.textContaining('/ ${MacroTargets.athletic.proteinGrams.round()} g'),
        findsOneWidget,
      );
    });

    testWidgets('the balance badge appears only on a complete plate',
        (WidgetTester tester) async {
      await pumpDock(tester, plate: _partialPlate);
      expect(find.byType(BalanceBadge), findsNothing);

      await pumpDock(tester, plate: _completePlate);
      expect(find.byType(BalanceBadge), findsOneWidget);
    });

    testWidgets('the action is inert but present while unfinished',
        (WidgetTester tester) async {
      await pumpDock(tester, plate: _partialPlate);
      final Finder action = find.byWidgetPredicate(
        (Widget w) => w is TactileFeedbackWell && w.semanticLabel == 'أكمل الأقسام',
      );
      expect(action, findsOneWidget);
      expect(tester.widget<TactileFeedbackWell>(action).enabled, isFalse);
    });

    testWidgets('the action carries the total once it is live',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final Money total = PriceBreakdown.forPlate(
        selection: _completePlate,
        mode: FulfilmentMode.delivery,
      ).total;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(fonts: _fonts),
          locale: const Locale('ar'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MacroCapsule(
                summary: _completePlate.summary,
                total: total,
                onScaleChanged: (_) {},
                onCheckout: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(total.format(AppLanguage.arabic)), findsOneWidget);
    });
  });
}
