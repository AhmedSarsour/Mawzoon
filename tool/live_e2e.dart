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
import 'package:mawzoon/features/kitchen_display/domain/kitchen_station.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_ticket.dart';
import 'package:mawzoon/features/manager_suite/application/back_office_store.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/services/idempotency_key.dart';
import 'package:mawzoon/services/server_menu_availability.dart';
import 'package:mawzoon/services/supabase_back_office.dart';
import 'package:mawzoon/services/supabase_kitchen_feed.dart';
import 'package:mawzoon/services/supabase_order_gateway.dart';
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
    payment: PaymentMethod.cash,
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

  final PlaceOrderOutcome again =
      await gateway.place(pickup, idempotencyKey: key);
  _check(
    again is OrderPlaced && again.replayed && again.orderId == placed.orderId,
    'same key replays the same order',
  );

  final PlaceOrderOutcome delivery = await gateway.place(
    pickup.copyWith(mode: FulfilmentMode.delivery, address: SavedPlaces.home),
    idempotencyKey: newIdempotencyKey(),
  );
  _check(
    delivery is OrderRefused && delivery.reason == RefusalReason.needsPhone,
    'delivery without a phone is refused with needs_phone',
  );

  final PlaceOrderOutcome delivered = await gateway.place(
    pickup
        .copyWith(mode: FulfilmentMode.delivery, address: SavedPlaces.home)
        .withPhone(saudiMobile('050 123 4567')),
    idempotencyKey: newIdempotencyKey(),
  );
  _check(
    delivered is OrderPlaced,
    'delivery with a phone is placed (got $delivered)',
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

  final List<KitchenTicket> start =
      await board.first.timeout(const Duration(seconds: 15));
  final KitchenTicket ticket = ticketIn(start);
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
