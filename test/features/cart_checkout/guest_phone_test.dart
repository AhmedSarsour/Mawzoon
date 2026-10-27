import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/guest_phone.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/saved_places.dart';
import 'package:mawzoon/features/cart_checkout/presentation/checkout_sheet.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/services/order_wire.dart';
import 'package:mawzoon/services/shared_preferences_phone_memory.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

final PlateSelection _plate = PlateSelection.empty
    .select(MawzoonCatalog.herbGrilledBreast)
    .select(MawzoonCatalog.steamedBasmati)
    .select(MawzoonCatalog.charredGardenVeggies);

Finder get _confirm => find.byWidgetPredicate(
      (Widget w) =>
          w is TactileFeedbackWell && w.semanticLabel == 'تأكيد الطلب',
    );

void main() {
  group('israeliMobile', () {
    test('accepts the ways people type it', () {
      for (final String typed in <String>[
        '0501234567',
        '501234567',
        '050-123-4567',
        '050 123 4567',
        '+972501234567',
        '+972 50-123-4567',
        '00972501234567',
        '972501234567',
        '٠٥٠١٢٣٤٥٦٧', // Arabic-Indic, from an Arabic keyboard
      ]) {
        expect(israeliMobile(typed), '+972501234567', reason: typed);
      }
    });

    test('refuses what a driver could not call', () {
      for (final String typed in <String>[
        '',
        '05012345',
        '05012345678',
        '0212345678', // landline prefix, not mobile
        '+966501234567', // Saudi, from an old install
        'call me',
      ]) {
        expect(israeliMobile(typed), isNull, reason: typed);
      }
    });

    test('reads back the local way, edits with the leading 0', () {
      expect(formatIsraeliMobile('+972501234567'), '050-123-4567');
      expect(localPart('+972501234567'), '0501234567');
      expect(localPart(null), '');
    });
  });

  test('delivery needs a phone; pickup does not; the request carries it', () {
    final OrderDraft delivery = OrderDraft(
      selection: _plate,
      mode: FulfilmentMode.delivery,
      payment: PaymentMethod.card,
      address: SavedPlaces.home,
    );
    expect(delivery.blocker, OrderDraft.needsPhoneBlocker);
    expect(delivery.copyWith(mode: FulfilmentMode.pickup).blocker, isNull);

    final OrderDraft withPhone = delivery.withPhone('+972501234567');
    expect(withPhone.blocker, isNull);
    expect(
      withPhone.copyWith(note: 'no onions').phone,
      '+972501234567',
      reason: 'copyWith keeps the phone',
    );
    expect(placeOrderPayload(withPhone)['customer_phone'], '+972501234567');
    expect(withPhone.withPhone(null).phone, isNull);
  });

  test('the remembered phone is re-validated on the way out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesPhoneMemory.key: 'garbage',
    });
    final SharedPreferencesPhoneMemory memory = SharedPreferencesPhoneMemory();
    expect(await memory.read(), isNull);
    await memory.write('+972501234567');
    expect(await memory.read(), '+972501234567');
  });

  group('the phone in the sheet', () {
    Future<void> open(WidgetTester tester, {String? phone}) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(fonts: _fonts),
          locale: const Locale('ar'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: Scaffold(
            body: CheckoutSheet(
              selection: _plate,
              phone: phone,
              offerDelivery: true,
              offerCard: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    bool enabled(WidgetTester tester) =>
        tester.widget<TactileFeedbackWell>(_confirm).enabled;

    testWidgets(
        'first delivery: the button names what is missing until a '
        'callable number is typed', (WidgetTester tester) async {
      await open(tester);
      expect(
        find.text(OrderDraft.needsPhoneBlocker.resolve(AppLanguage.arabic)),
        findsOneWidget,
      );
      expect(enabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), '05012');
      await tester.pump();
      expect(enabled(tester), isFalse, reason: 'half a number is no number');

      await tester.enterText(find.byType(TextField), '0501234567');
      await tester.pump();
      expect(enabled(tester), isTrue);
    });

    testWidgets('pickup never asks', (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text(FulfilmentMode.pickup.label.ar));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsNothing);
      expect(enabled(tester), isTrue);
    });

    testWidgets('remembered: one line, and "change" opens it pre-filled',
        (WidgetTester tester) async {
      await open(tester, phone: '+972501234567');
      expect(find.byType(TextField), findsNothing);
      expect(find.text('050-123-4567'), findsOneWidget);
      expect(enabled(tester), isTrue);

      await tester.tap(find.text('تغيير'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '0501234567',
      );
      expect(enabled(tester), isTrue, reason: 'still the same valid number');
    });
  });
}
