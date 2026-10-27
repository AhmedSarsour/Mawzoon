import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/stock_status.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/core/pricing/money.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_placement.dart';
import 'package:mawzoon/features/cart_checkout/domain/saved_places.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';
import 'package:mawzoon/features/curated_menu/domain/signature_plate.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/services/idempotency_key.dart';
import 'package:mawzoon/services/order_wire.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

final PlateSelection _custom = PlateSelection.empty
    .select(MawzoonCatalog.grilledSalmon)
    .select(MawzoonCatalog.steamedBasmati)
    .select(MawzoonCatalog.charredGardenVeggies);

OrderDraft _draft(
  PlateSelection selection, {
  FulfilmentMode mode = FulfilmentMode.pickup,
}) =>
    OrderDraft(
      selection: selection,
      mode: mode,
      payment: PaymentMethod.counter,
      address: SavedPlaces.home,
    );

PostgrestException _pg(
  String message, {
  String code = 'P0001',
  Object? details,
  String? hint,
}) =>
    PostgrestException(
      message: message,
      code: code,
      details: details,
      hint: hint,
    );

void main() {
  group('placeOrderPayload', () {
    test('a custom pickup sends choices, never a price', () {
      final Map<String, Object?> p = placeOrderPayload(_draft(_custom));
      expect(p['order_type'], 'PICKUP');
      expect(p['payment_method'], 'counter');
      expect(p['volume'], 'STANDARD');
      expect(p['protein_id'], MawzoonCatalog.grilledSalmon.id);
      expect(p['carb_id'], MawzoonCatalog.steamedBasmati.id);
      expect(p['fiber_id'], MawzoonCatalog.charredGardenVeggies.id);
      expect(p.containsKey('signature_plate_id'), isFalse);
      expect(
        p.containsKey('delivery_address'),
        isFalse,
        reason: 'pickup sends no address even though the draft keeps one',
      );
      expect(p.keys.where((String k) => k.contains('price')), isEmpty);
      expect(p['title'], contains(MawzoonCatalog.grilledSalmon.name.ar));
    });

    test('a plate equal to a chef plate is sent as that chef plate', () {
      final SignaturePlate chef = SignaturePlateCatalog.all.first;
      final Map<String, Object?> p = placeOrderPayload(
        _draft(chef.selectionAt(PortionScale.athleticLoad)),
      );
      expect(p['signature_plate_id'], chef.id);
      expect(p['title'], chef.name.ar);
      expect(p['volume'], 'ATHLETIC');
    });

    test('delivery joins the address the way a driver reads it', () {
      final Map<String, Object?> p = placeOrderPayload(
        _draft(_custom, mode: FulfilmentMode.delivery),
      );
      const DeliveryAddress home = SavedPlaces.home;
      expect(p['order_type'], 'DELIVERY');
      expect(
        p['delivery_address'],
        '${home.line}، ${home.district}، ${home.directions}',
      );
    });

    test('nutrition is the figure the guest saw', () {
      final OrderDraft draft = _draft(_custom);
      final Map<String, Object?> nutrition =
          placeOrderPayload(draft)['nutrition']! as Map<String, Object?>;
      expect(nutrition['calories'], draft.summary.displayKilocalories);
      expect(
        nutrition['protein_g'],
        closeTo(draft.summary.totalMacros.proteinGrams, 0.05),
      );
    });
  });

  group('outcomeFromError', () {
    test('sold_out names the component', () {
      final PlaceOrderOutcome o = outcomeFromError(
        _pg('sold_out', details: MawzoonCatalog.grilledSalmon.id),
      );
      expect(o, isA<OrderRefused>());
      final OrderRefused r = o as OrderRefused;
      expect(r.reason, RefusalReason.soldOut);
      expect(
        r.message,
        OrderDraft.soldOutBlocker(MawzoonCatalog.grilledSalmon),
      );
      expect(r.retryable, isFalse);
    });

    test('each server key maps to its reason', () {
      expect(
        (outcomeFromError(_pg('menu_changed')) as OrderRefused).reason,
        RefusalReason.menuChanged,
      );
      expect(
        (outcomeFromError(_pg('needs_phone')) as OrderRefused).reason,
        RefusalReason.needsPhone,
      );
      expect(
        (outcomeFromError(_pg('needs_address')) as OrderRefused).reason,
        RefusalReason.needsAddress,
      );
    });

    test('unpaid_order_open names the open order', () {
      final OrderRefused r = outcomeFromError(
        _pg('unpaid_order_open', details: 'order-uuid', hint: '204'),
      ) as OrderRefused;
      expect(r.reason, RefusalReason.unpaidOrderOpen);
      expect(r.openOrderId, 'order-uuid');
      expect(r.openOrderNumber, 204);
      expect(r.retryable, isFalse);
    });

    test('counter_blocked is its own reason, not a retry', () {
      final OrderRefused r =
          outcomeFromError(_pg('counter_blocked')) as OrderRefused;
      expect(r.reason, RefusalReason.counterBlocked);
      expect(r.retryable, isFalse);
    });

    test('a Postgres answer we did not expect: nothing placed, retryable', () {
      final OrderRefused r =
          outcomeFromError(_pg('new row violates check', code: '23514'))
              as OrderRefused;
      expect(r.reason, RefusalReason.couldNotSend);
      expect(r.retryable, isTrue);
    });

    test('no answer, or only a proxy status, is unreachable', () {
      expect(
        outcomeFromError(const SocketException('down')),
        isA<OrderUnreachable>(),
      );
      expect(
        outcomeFromError(TimeoutException('slow')),
        isA<OrderUnreachable>(),
      );
      expect(
        outcomeFromError(_pg('Bad Gateway', code: '502')),
        isA<OrderUnreachable>(),
      );
    });
  });

  test('orderPlacedFrom reads the server total and number', () {
    final OrderPlaced placed = orderPlacedFrom(<String, dynamic>{
      'order_id': 'abc',
      'order_number': 123,
      'total_minor_units': 7015,
      'replayed': true,
    });
    expect(placed.code, 'M-123');
    expect(placed.total, const Money(7015));
    expect(placed.replayed, isTrue);
    expect(placed.awaitingPayment, isFalse);
    expect(placed.paymentDueAt, isNull);
  });

  test('orderPlacedFrom reads an unpaid order and its deadline', () {
    final OrderPlaced placed = orderPlacedFrom(<String, dynamic>{
      'order_id': 'abc',
      'order_number': 124,
      'total_minor_units': 4900,
      'replayed': false,
      'status': 'AWAITING_PAYMENT',
      'payment_method': 'counter',
      'payment_due_at': '2026-10-22T20:45:00.123+00:00',
    });
    expect(placed.awaitingPayment, isTrue);
    expect(
      placed.paymentDueAt,
      DateTime.utc(2026, 10, 22, 20, 45, 0, 123),
    );
  });

  test('availabilityFromRows keeps reasons and never invents a sale', () {
    final MenuAvailability a = availabilityFromRows(<dynamic>[
      <String, dynamic>{
        'component_id': 'x',
        'status': 'soldOut',
        'sold_out_reason': 'takenOff',
      },
      <String, dynamic>{
        'component_id': 'y',
        'status': 'soldOut',
        'sold_out_reason': 'belowSafetyBuffer',
      },
      <String, dynamic>{
        'component_id': 'z',
        'status': 'runningLow',
        'sold_out_reason': null,
      },
      <String, dynamic>{
        'component_id': 'w',
        'status': 'inStock',
        'sold_out_reason': null,
      },
    ]);
    expect((a.statusOf('x') as SoldOut).reason, SoldOutReason.takenOff);
    expect(
      (a.statusOf('y') as SoldOut).reason,
      SoldOutReason.belowSafetyBuffer,
    );
    expect(a.canOrder('x'), isFalse);
    expect(a.canOrder('z'), isTrue);
    expect(a.statusOf('z'), isA<RunningLow>());
    expect(a.canOrder('w'), isTrue);
  });

  test('idempotency keys are v4 UUIDs and do not repeat', () {
    final RegExp v4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final Set<String> keys = <String>{
      for (int i = 0; i < 500; i++) newIdempotencyKey(),
    };
    expect(keys, hasLength(500));
    expect(keys.every(v4.hasMatch), isTrue);
    expect(newIdempotencyKey(Random(1)), newIdempotencyKey(Random(1)));
  });
}
