import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/stock_status.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_placement.dart';
import 'package:mawzoon/features/cart_checkout/presentation/checkout_sheet.dart';
import 'package:mawzoon/features/order_home/presentation/order_home_screen.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/main.dart';
import 'package:mawzoon/services/server_menu_availability.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _NeverCalled implements OrderGateway {
  @override
  Future<PlaceOrderOutcome> place(
    OrderDraft draft, {
    required String idempotencyKey,
  }) =>
      throw StateError('not expected');
}

void main() {
  // Regression: the menu scope used to sit inside `home`, so the checkout
  // sheet (a route pushed above home) never saw it and treated everything as
  // in stock. The server's sold-out must reach the sheet.
  testWidgets('the checkout sheet sees the server\'s sold-out',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ServerMenuAvailability availability = ServerMenuAvailability(
      ensureSession: () async => false,
    );
    await tester.pumpWidget(
      MawzoonApp(orders: _NeverCalled(), availability: availability),
    );
    await tester.pump(const Duration(seconds: 1));

    availability.value = const MenuAvailability(<String, StockStatus>{
      'carb.steamed_basmati': SoldOut(
        reason: SoldOutReason.belowSafetyBuffer,
        portionsRemaining: 0,
      ),
    });
    await tester.pump();

    final BuildContext home = tester.element(find.byType(OrderHomeScreen));
    unawaited(
      showCheckoutSheet(
        home,
        selection: PlateSelection.empty
            .select(MawzoonCatalog.herbGrilledBreast)
            .select(MawzoonCatalog.steamedBasmati)
            .select(MawzoonCatalog.charredGardenVeggies),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.text(
        OrderDraft.soldOutBlocker(MawzoonCatalog.steamedBasmati)
            .resolve(AppLanguage.arabic),
      ),
      findsOneWidget,
    );
  });
}
