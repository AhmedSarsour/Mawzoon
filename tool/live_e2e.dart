// End-to-end check of the app's real Supabase code against the live project.
// Run through tool/live_e2e.sh, which creates a throwaway staff account and stock,
// runs this in Chrome, and deletes everything afterwards. Prints E2E PASS / E2E FAIL.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_placement.dart';
import 'package:mawzoon/features/cart_checkout/domain/saved_places.dart';
import 'package:mawzoon/features/counter_desk/domain/counter_payment.dart';
import 'package:mawzoon/features/counter_desk/domain/unpaid_order.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_station.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_ticket.dart';
import 'package:mawzoon/features/manager_suite/application/back_office_store.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/order_tracking/domain/tracked_order.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/services/idempotency_key.dart';
import 'package:mawzoon/services/server_menu_availability.dart';
import 'package:mawzoon/services/supabase_back_office.dart';
import 'package:mawzoon/services/supabase_counter_desk.dart';
import 'package:mawzoon/services/supabase_kitchen_feed.dart';
import 'package:mawzoon/services/supabase_order_gateway.dart';
import 'package:mawzoon/services/supabase_order_tracker.dart';
import 'package:mawzoon/services/supabase_unpaid_orders.dart';
import 'package:mawzoon/services/supabase_service.dart';
import 'package:mawzoon/services/supabase_staff_auth.dart';
import 'package:mawzoon/features/staff_auth/domain/staff_auth.dart';
import 'package:mawzoon/features/cart_checkout/domain/guest_phone.dart';

const String _staffEmail = String.fromEnvironment('E2E_STAFF_EMAIL');
const String _staffPassword = String.fromEnvironment('E2E_STAFF_PASSWORD');

final PlateSelection _plate = PlateSelection.empty
    .select(MawzoonCatalog.herbGrilledBreast)
    .select(MawzoonCatalog.steamedBasmati)
    .select(MawzoonCatalog.charredGardenVeggies);

void _check(bool ok, String what) {
  if (!ok) throw StateError(what);
  // ignore: avoid_print
  print('  ok  $what');
}

const Duration _wait = Duration(seconds: 15);

/// A new order from whoever is signed in (a fresh anonymous guest if nobody).
Future<OrderPlaced> _placeFresh(
  SupabaseOrderGateway gateway,
  OrderDraft draft,
) async {
  final PlaceOrderOutcome out =
      await gateway.place(draft, idempotencyKey: newIdempotencyKey());
  _check(out is OrderPlaced, 'another guest places an order (got $out)');
  return out as OrderPlaced;
}

/// Polls until [done] (a realtime push is async), failing after [_wait].
Future<void> _until(bool Function() done) async {
  final Stopwatch clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > _wait) throw StateError('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _run();
    // ignore: avoid_print
    print('E2E PASS');
  } catch (error, stack) {
    // ignore: avoid_print
    print('E2E FAIL: $error\n$stack');
  }
}

Future<void> _run() async {
  _check(await SupabaseService.initialize(), 'Supabase starts');
  final auth = SupabaseService.client.auth;
  await auth.signOut();

  // ── Guest ────────────────────────────────────────────────────────────────
  _check(
    await SupabaseService.ensureSession(),
    'guest gets an anonymous session',
  );
  _check(auth.currentUser!.isAnonymous, 'that session is anonymous');
  _check(!await SupabaseService.isStaffSession(), 'a guest is not staff');

  final ServerMenuAvailability menu = ServerMenuAvailability();
  await menu.refresh();
  _check(
    menu.value.canOrder(MawzoonCatalog.herbGrilledBreast.id),
    'stocked protein is orderable',
  );
  _check(
    !menu.value.canOrder(MawzoonCatalog.grilledSalmon.id),
    'unstocked salmon is sold out',
  );
  menu.dispose();

  final SupabaseOrderGateway gateway = SupabaseOrderGateway();
  final OrderDraft pickup = OrderDraft(
    selection: _plate,
    mode: FulfilmentMode.pickup,
    payment: PaymentMethod.counter,
  );
  // Refusals first: once the guest has an unpaid order open, the server
  // answers unpaid_order_open before checking anything else.
  // Delivery and card are switched off live (LaunchSwitches): the server
  // refuses them even when a build asks.
  final PlaceOrderOutcome delivery = await gateway.place(
    pickup
        .copyWith(
          mode: FulfilmentMode.delivery,
          payment: PaymentMethod.card,
          address: SavedPlaces.home,
        )
        .withPhone(israeliMobile('050-123-4567')),
    idempotencyKey: newIdempotencyKey(),
  );
  _check(
    delivery is OrderRefused &&
        delivery.reason == RefusalReason.optionUnavailable,
    'delivery is refused while switched off (got $delivery)',
  );

  final PlaceOrderOutcome card = await gateway.place(
    pickup.copyWith(payment: PaymentMethod.card),
    idempotencyKey: newIdempotencyKey(),
  );
  _check(
    card is OrderRefused && card.reason == RefusalReason.optionUnavailable,
    'card is refused while switched off (got $card)',
  );

  final PlaceOrderOutcome salmon = await gateway.place(
    pickup.copyWith(selection: _plate.select(MawzoonCatalog.grilledSalmon)),
    idempotencyKey: newIdempotencyKey(),
  );
  _check(
    salmon is OrderRefused &&
        salmon.reason == RefusalReason.soldOut &&
        salmon.componentId == MawzoonCatalog.grilledSalmon.id,
    'sold-out salmon is refused and named',
  );

  final String key = newIdempotencyKey();
  final PlaceOrderOutcome first =
      await gateway.place(pickup, idempotencyKey: key);
  _check(first is OrderPlaced, 'pickup order placed (got $first)');
  final OrderPlaced placed = first as OrderPlaced;
  _check(
    placed.total == pickup.price.total,
    'server total ${placed.total} == app total ${pickup.price.total}',
  );
  _check(
    placed.awaitingPayment &&
        placed.paymentDueAt!.difference(DateTime.now()).inMinutes >= 40,
    'a new order waits for payment, about 45 minutes',
  );

  final PlaceOrderOutcome again =
      await gateway.place(pickup, idempotencyKey: key);
  _check(
    again is OrderPlaced && again.replayed && again.orderId == placed.orderId,
    'same key replays the same order',
  );

  final PlaceOrderOutcome second =
      await gateway.place(pickup, idempotencyKey: newIdempotencyKey());
  _check(
    second is OrderRefused &&
        second.reason == RefusalReason.unpaidOrderOpen &&
        second.openOrderId == placed.orderId &&
        second.openOrderNumber == placed.orderNumber,
    'a second order while one is unpaid is refused and names it',
  );

  // ── Guest tracking: what the receipt and tracking screens read ───────────
  final SupabaseOrderTracker tracker = SupabaseOrderTracker();
  final TrackedOrder? open = await tracker.openOrder();
  _check(
    open != null &&
        open.id == placed.orderId &&
        open.stage == OrderStage.awaitingPayment &&
        open.total == placed.total &&
        open.dueAt != null &&
        open.title.isNotEmpty,
    'the open order reads back with total, deadline and plate',
  );
  final TrackedOrder? watched =
      await tracker.watch(placed.orderId).first.timeout(_wait);
  _check(watched?.code == placed.code, 'the tracking stream emits the order');

  // A second guest places an order, then cancels it while unpaid.
  await auth.signOut();
  final OrderPlaced b = await _placeFresh(gateway, pickup);
  final List<TrackedOrder?> bSeen = <TrackedOrder?>[];
  final StreamSubscription<TrackedOrder?> bSub =
      tracker.watch(b.orderId).listen(bSeen.add);
  await _until(() => bSeen.isNotEmpty);
  _check(
    await tracker.cancel(b.orderId) == CancelResult.cancelled,
    'a guest cancels their unpaid order',
  );
  await _until(
    () => bSeen.any((TrackedOrder? o) => o?.stage == OrderStage.cancelled),
  );
  await bSub.cancel();
  _check(
    bSeen.last?.cancelReason == CancelReason.guest,
    'the tracking stream pushes the cancel (realtime) with its reason',
  );
  _check(
    await tracker.cancel(b.orderId) == CancelResult.alreadyCancelled,
    'a second cancel reads already cancelled',
  );
  _check(await tracker.openOrder() == null, 'a cancelled order is not open');

  // A third guest leaves one unpaid for the counter's list.
  await auth.signOut();
  final OrderPlaced c = await _placeFresh(gateway, pickup);

  // ── Kitchen ──────────────────────────────────────────────────────────────
  await auth.signOut();
  final SupabaseStaffAuth staff = SupabaseStaffAuth();
  final (StaffAccess? wrong, StaffSignInFailure? why) =
      await staff.signIn(email: _staffEmail, password: 'not-the-password');
  _check(
    wrong == null && why == StaffSignInFailure.wrongCredentials,
    'a wrong staff password is refused as wrong credentials',
  );
  final (StaffAccess? access, _) =
      await staff.signIn(email: _staffEmail, password: _staffPassword);
  _check(access is StaffSignedIn, 'staff sign-in lands signed in as staff');

  final SupabaseKitchenFeed feed = SupabaseKitchenFeed();
  final Stream<List<KitchenTicket>> board = feed.watch();
  KitchenTicket ticketIn(List<KitchenTicket> tickets) =>
      tickets.firstWhere((KitchenTicket t) => t.code == placed.code);

  final List<KitchenTicket> unpaid =
      await board.first.timeout(const Duration(seconds: 15));
  _check(
    unpaid.every((KitchenTicket t) => t.code != placed.code),
    'kitchen does not see ${placed.code} before it is paid',
  );

  final SupabaseUnpaidOrders unpaidFeed = SupabaseUnpaidOrders();
  final List<UnpaidOrder> waiting = await unpaidFeed.watch().first.timeout(_wait);
  UnpaidOrder? waitingFor(List<UnpaidOrder> l, String id) {
    for (final UnpaidOrder o in l) {
      if (o.id == id) return o;
    }
    return null;
  }

  _check(
    waitingFor(waiting, placed.orderId)?.total == placed.total &&
        waitingFor(waiting, c.orderId) != null &&
        waitingFor(waiting, b.orderId) == null,
    'the counter lists unpaid orders, not the cancelled one',
  );

  final SupabaseCounterDesk desk = SupabaseCounterDesk();
  _check(
    await desk.markPaid(placed.orderId) == CounterPayResult.paid,
    'cashier marks ${placed.code} paid',
  );
  _check(
    await desk.markPaid(placed.orderId) == CounterPayResult.alreadyPaid,
    'a second tap reads already paid',
  );

  final Future<List<UnpaidOrder>> afterPay = unpaidFeed.watch().firstWhere(
    (List<UnpaidOrder> l) => waitingFor(l, placed.orderId) == null,
  );
  await unpaidFeed.refresh();
  final List<UnpaidOrder> stillWaiting = await afterPay.timeout(_wait);
  _check(
    waitingFor(stillWaiting, c.orderId) != null,
    'a paid order leaves the counter list; the other stays',
  );
  unpaidFeed.dispose();

  final Future<List<KitchenTicket>> paid = board.firstWhere(
    (List<KitchenTicket> t) =>
        t.any((KitchenTicket k) => k.code == placed.code),
  );
  await feed.refresh();
  final KitchenTicket ticket =
      ticketIn(await paid.timeout(const Duration(seconds: 15)));
  _check(
    ticket.instructions.length == 3 && ticket.status.prepped.isEmpty,
    'kitchen sees ${placed.code} with three stations to make',
  );

  for (final KitchenStation station in KitchenStation.values) {
    await feed.setStation(placed.code, station, done: true);
  }
  await feed.markPlated(placed.code);
  final Future<List<KitchenTicket>> afterPlate = board.firstWhere(
    (List<KitchenTicket> t) => ticketIn(t).status.isArchived,
  );
  await feed.refresh();
  await afterPlate.timeout(const Duration(seconds: 15));
  _check(true, 'plated ticket moves to packaging (READY), seen via the feed');

  await feed.markCollected(placed.code);
  final Map<String, dynamic> row = await SupabaseService.client
      .from('orders')
      .select('status')
      .eq('id', placed.orderId)
      .single();
  _check(row['status'] == 'COMPLETED', 'collected order is COMPLETED');
  feed.dispose();

  // ── Back office ──────────────────────────────────────────────────────────
  final SupabaseBackOffice office = SupabaseBackOffice();
  final BackOfficeSnapshot before = await office.load();
  final int oil = before.stockMinorUnits[RawStore.oliveOil.id]!;
  await office.adjust(
    RawStore.oliveOil.id,
    Quantity.millilitres(250).minorUnits,
  );
  final BackOfficeSnapshot after = await office.load();
  _check(
    after.stockMinorUnits[RawStore.oliveOil.id] == oil + 250000,
    'a delivery adds to the book',
  );

  await office.setForcedOff(MawzoonCatalog.steamedBasmati.id, off: true);
  _check(
    (await office.load()).forcedOff.contains(MawzoonCatalog.steamedBasmati.id),
    'taking basmati off is saved',
  );
  await office.setForcedOff(MawzoonCatalog.steamedBasmati.id, off: false);
  office.dispose();
  await auth.signOut();
}
