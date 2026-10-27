import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/menu/ingredient_option.dart';
import '../core/menu/stock_status.dart';
import '../core/nutrition/nutritional_summary.dart';
import '../core/nutrition/portion_scale.dart';
import '../core/pricing/money.dart';
import '../features/cart_checkout/domain/delivery_address.dart';
import '../features/cart_checkout/domain/order_draft.dart';
import '../features/cart_checkout/domain/order_placement.dart';
import '../features/curated_menu/data/signature_plate_catalog.dart';
import '../features/curated_menu/domain/signature_plate.dart';
import '../features/plate_builder/domain/plate_selection.dart';

// How the app's domain types read on the wire to Postgres
// (supabase/migrations/20261019140000_module11_place_order.sql). Pure functions:
// no client, no I/O, so every mapping is unit-tested.

/// `volume_type` for [scale].
String serverVolume(PortionScale scale) => switch (scale) {
      PortionScale.standardBalance => 'STANDARD',
      PortionScale.athleticLoad => 'ATHLETIC',
    };

/// `order_type` for [mode].
String serverOrderType(FulfilmentMode mode) => switch (mode) {
      FulfilmentMode.delivery => 'DELIVERY',
      FulfilmentMode.pickup => 'PICKUP',
    };

/// The chef's plate [selection] is, if its three components are exactly one.
///
/// Matched on components rather than on how the guest got there: a plate built
/// by hand that happens to equal a signature *is* that signature to the kitchen.
SignaturePlate? signaturePlateFor(PlateSelection selection) {
  for (final SignaturePlate plate in SignaturePlateCatalog.all) {
    if (plate.protein == selection.protein &&
        plate.carb == selection.carb &&
        plate.fiber == selection.fiber) {
      return plate;
    }
  }
  return null;
}

double _oneDecimal(double value) => (value * 10).round() / 10;

/// The `p_order` argument of `place_order` for [draft]. [draft] must be complete.
Map<String, Object?> placeOrderPayload(OrderDraft draft) {
  final PlateSelection selection = draft.selection;
  final ProteinOption protein = selection.protein!;
  final CarbOption carb = selection.carb!;
  final FiberOption fiber = selection.fiber!;
  final SignaturePlate? signature = signaturePlateFor(selection);
  final NutritionalSummary summary = draft.summary;
  final DeliveryAddress? address = draft.address;

  return <String, Object?>{
    'order_type': serverOrderType(draft.mode),
    'payment_method': draft.payment.name,
    'volume': serverVolume(selection.scale),
    'protein_id': protein.id,
    'carb_id': carb.id,
    'fiber_id': fiber.id,
    if (signature != null) 'signature_plate_id': signature.id,
    // The kitchen reads Arabic; the components themselves carry the detail.
    'title': signature?.name.ar ??
        <String>[protein.name.ar, carb.name.ar, fiber.name.ar].join(' · '),
    if (draft.mode == FulfilmentMode.delivery && address != null)
      'delivery_address': <String>[
        address.line,
        address.district,
        if (address.directions != null) address.directions!,
      ].join('، '),
    if (draft.phone != null) 'customer_phone': draft.phone,
    if (draft.note != null) 'note': draft.note,
    'nutrition': <String, Object>{
      'calories': summary.displayKilocalories,
      'protein_g': _oneDecimal(summary.totalMacros.proteinGrams),
      'carbs_g': _oneDecimal(summary.totalMacros.carbohydrateGrams),
      'fats_g': _oneDecimal(summary.totalMacros.fatGrams),
    },
  };
}

/// `place_order`'s success answer.
OrderPlaced orderPlacedFrom(Map<String, dynamic> row) => OrderPlaced(
      orderId: row['order_id'] as String,
      orderNumber: (row['order_number'] as num).toInt(),
      total: Money((row['total_minor_units'] as num).toInt()),
      replayed: row['replayed'] as bool? ?? false,
      awaitingPayment: row['status'] == 'AWAITING_PAYMENT',
      paymentDueAt: switch (row['payment_due_at']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
    );

/// What a failed `place_order` call means for the guest.
///
/// An error Postgres answered (a SQLSTATE or PostgREST code) means the
/// transaction rolled back: nothing was placed. No network, a timeout, or a bare
/// HTTP status from a proxy is unreachable instead: the order may have landed,
/// and the same key makes the retry safe.
PlaceOrderOutcome outcomeFromError(Object error) {
  if (error is! PostgrestException) return const OrderUnreachable();
  final String? code = error.code;
  if (code == null || RegExp(r'^\d{3}$').hasMatch(code)) {
    return const OrderUnreachable();
  }
  return switch (error.message) {
    'sold_out' => OrderRefused(
        RefusalReason.soldOut,
        componentId: error.details is String ? error.details! as String : null,
      ),
    'menu_changed' => const OrderRefused(RefusalReason.menuChanged),
    'needs_phone' => const OrderRefused(RefusalReason.needsPhone),
    'needs_address' => const OrderRefused(RefusalReason.needsAddress),
    'delivery_unavailable' ||
    'card_unavailable' ||
    'card_required' =>
      const OrderRefused(RefusalReason.optionUnavailable),
    // detail = the open order's id, hint = its number.
    'unpaid_order_open' => OrderRefused(
        RefusalReason.unpaidOrderOpen,
        openOrderId: error.details is String ? error.details! as String : null,
        openOrderNumber: int.tryParse(error.hint ?? ''),
      ),
    'counter_blocked' => const OrderRefused(RefusalReason.counterBlocked),
    _ => const OrderRefused(RefusalReason.couldNotSend),
  };
}

/// `menu_availability()` rows as the app's snapshot.
///
/// The server sends a status, never a count, so the counts here are
/// placeholders. Nothing on a guest screen reads them.
MenuAvailability availabilityFromRows(List<dynamic> rows) =>
    MenuAvailability(<String, StockStatus>{
      for (final Map<String, dynamic> row in rows.cast<Map<String, dynamic>>())
        row['component_id'] as String: switch (row['status']) {
          'soldOut' => SoldOut(
              reason: row['sold_out_reason'] == 'takenOff'
                  ? SoldOutReason.takenOff
                  : SoldOutReason.belowSafetyBuffer,
              portionsRemaining: 0,
            ),
          'runningLow' => const RunningLow(portionsRemaining: 1),
          _ => const InStock(portionsRemaining: 999),
        },
    });
