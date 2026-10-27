import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/pricing/money.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_placement.dart';
import 'package:mawzoon/features/cart_checkout/presentation/checkout_sheet.dart';
import 'package:mawzoon/features/cart_checkout/presentation/order_gateway_scope.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

final PlateSelection _plate = PlateSelection.empty
    .select(MawzoonCatalog.herbGrilledBreast)
    .select(MawzoonCatalog.steamedBasmati)
    .select(MawzoonCatalog.charredGardenVeggies);

/// Answers each place() with the next scripted outcome, recording the keys.
final class _ScriptedGateway implements OrderGateway {
  _ScriptedGateway(this._script);

  final List<PlaceOrderOutcome> _script;
  final List<String> keys = <String>[];

  @override
  Future<PlaceOrderOutcome> place(
    OrderDraft draft, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    return _script.removeAt(0);
  }
}

const OrderPlaced _placed = OrderPlaced(
  orderId: 'id-1',
  orderNumber: 104,
  total: Money(5635),
);

Finder get _confirm => find.byWidgetPredicate(
      (Widget w) =>
          w is TactileFeedbackWell && w.semanticLabel == 'تأكيد الطلب',
    );

void main() {
  late _ScriptedGateway gateway;
  late int staleCalls;
  CheckoutResult? result;

  Future<void> open(WidgetTester tester, List<PlaceOrderOutcome> script) async {
    gateway = _ScriptedGateway(script);
    staleCalls = 0;
    result = null;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(fonts: _fonts),
        locale: const Locale('ar'),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        // Above the navigator, as in main.dart, so the sheet's route sees it.
        builder: (BuildContext context, Widget? app) => OrderGatewayScope(
          gateway: gateway,
          onMenuStale: () => staleCalls++,
          child: app!,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showCheckoutSheet(
                    context,
                    selection: _plate,
                    phone: '+972501234567',
                    // Edits below switch modes, so the full sheet is shown.
                    offerDelivery: true,
                    offerCard: true,
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
  }

  Future<void> tapPlace(WidgetTester tester) async {
    await tester.tap(_confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<TactileFeedbackWell>(_confirm).enabled;

  testWidgets('closes only on the kitchen\'s yes, carrying its number',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[_placed]);
    await tapPlace(tester);

    expect(result, isNotNull);
    expect(result!.placed!.code, 'M-104');
    expect(gateway.keys, hasLength(1));
  });

  testWidgets('a last-second sell-out says which dish, and refreshes the menu',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[
      OrderRefused(
        RefusalReason.soldOut,
        componentId: MawzoonCatalog.steamedBasmati.id,
      ),
    ]);
    await tapPlace(tester);

    expect(result, isNull, reason: 'the sheet stays open');
    expect(
      find.text(
        OrderDraft.soldOutBlocker(MawzoonCatalog.steamedBasmati)
            .resolve(AppLanguage.arabic),
      ),
      findsOneWidget,
    );
    expect(enabled(tester), isFalse);
    expect(staleCalls, 1);
  });

  testWidgets('counter paused for this guest: the sheet says why and stays',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[
      const OrderRefused(RefusalReason.counterBlocked),
    ]);
    await tapPlace(tester);

    expect(result, isNull, reason: 'nothing was placed; the sheet stays');
    expect(
      find.text(
        const OrderRefused(RefusalReason.counterBlocked)
            .message
            .resolve(AppLanguage.arabic),
      ),
      findsOneWidget,
    );
    expect(enabled(tester), isFalse);
  });

  testWidgets('an unpaid order already open: the sheet hands back its id',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[
      const OrderRefused(
        RefusalReason.unpaidOrderOpen,
        openOrderId: 'o-7',
        openOrderNumber: 7,
      ),
    ]);
    await tapPlace(tester);

    expect(result, isNotNull, reason: 'the sheet closes so home can jump');
    expect(result!.openOrderId, 'o-7');
    expect(result!.placed, isNull);
  });

  testWidgets('no answer: says so, stays live, and retries with the same key',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[const OrderUnreachable(), _placed]);
    await tapPlace(tester);

    expect(result, isNull);
    expect(
      find.text(OrderUnreachable.message.resolve(AppLanguage.arabic)),
      findsOneWidget,
    );
    expect(enabled(tester), isTrue);

    // Even after an edit: the first attempt may have landed, so its key holds.
    await tester.tap(find.text(FulfilmentMode.pickup.label.ar));
    await tester.pump(const Duration(milliseconds: 300));
    await tapPlace(tester);

    expect(result!.placed, _placed);
    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[1], gateway.keys[0]);
  });

  testWidgets('after a definite "no", an edited order gets a fresh key',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[
      const OrderRefused(RefusalReason.couldNotSend),
      _placed,
    ]);
    await tapPlace(tester);
    expect(enabled(tester), isTrue, reason: 'couldNotSend is retryable');

    await tester.tap(find.text(FulfilmentMode.pickup.label.ar));
    await tester.pump(const Duration(milliseconds: 300));
    await tapPlace(tester);

    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[1], isNot(gateway.keys[0]));
  });

  testWidgets('a refusal the guest can fix clears when they fix it',
      (WidgetTester tester) async {
    await open(tester, <PlaceOrderOutcome>[
      const OrderRefused(RefusalReason.menuChanged),
    ]);
    await tapPlace(tester);
    expect(enabled(tester), isFalse);

    await tester.tap(find.text(FulfilmentMode.pickup.label.ar));
    await tester.pump(const Duration(milliseconds: 300));
    expect(enabled(tester), isTrue);
  });
}
