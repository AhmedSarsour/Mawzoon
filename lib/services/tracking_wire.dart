import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/pricing/money.dart';
import '../features/counter_desk/domain/unpaid_order.dart';
import '../features/order_tracking/domain/tracked_order.dart';

// How `orders` rows read for the guest's tracking screen and the counter's
// unpaid list. Pure: no client, so every mapping is unit-tested.

/// Columns the guest tracking screen reads.
const String trackedOrderColumns =
    'id, order_number, order_type, status, total_price_minor_units, '
    'payment_due_at, cancel_reason, order_items(title)';

/// Statuses a guest still has something to wait for.
const List<String> openOrderStatuses = <String>[
  'AWAITING_PAYMENT',
  'PENDING',
  'ACCEPTED',
  'ASSEMBLING',
  'READY',
];

/// `orders.status` as the guest's stage. Unknown values read as paid, never as
/// "waiting for payment": a wrong "pay now" is worse than a vague "received".
OrderStage stageFromStatus(String? status) => switch (status) {
      'AWAITING_PAYMENT' => OrderStage.awaitingPayment,
      'ASSEMBLING' => OrderStage.making,
      'READY' => OrderStage.ready,
      'COMPLETED' => OrderStage.done,
      'CANCELLED' => OrderStage.cancelled,
      _ => OrderStage.paid,
    };

/// A tracked order from an `orders` row.
TrackedOrder trackedOrderFromRow(Map<String, dynamic> row) => TrackedOrder(
      id: row['id'] as String,
      number: (row['order_number'] as num).toInt(),
      stage: stageFromStatus(row['status'] as String?),
      total: Money((row['total_price_minor_units'] as num).toInt()),
      dueAt: _time(row['payment_due_at']),
      cancelReason: switch (row['cancel_reason']) {
        'guest' => CancelReason.guest,
        'staff' => CancelReason.staff,
        'expired' => CancelReason.expired,
        _ => null,
      },
      title: _firstTitle(row['order_items']),
      isDelivery: row['order_type'] == 'DELIVERY',
    );

/// Columns the counter's unpaid list reads.
const String unpaidOrderColumns =
    'id, order_number, order_type, total_price_minor_units, payment_due_at, '
    'created_at, order_items(title)';

/// An unpaid order from an `orders` row.
UnpaidOrder unpaidOrderFromRow(Map<String, dynamic> row) => UnpaidOrder(
      id: row['id'] as String,
      number: (row['order_number'] as num).toInt(),
      total: Money((row['total_price_minor_units'] as num).toInt()),
      dueAt: _time(row['payment_due_at']),
      createdAt: _time(row['created_at']),
      title: _firstTitle(row['order_items']),
    );

/// The plate's title: the order's first item (an order has one plate today).
String _firstTitle(Object? items) {
  if (items is List && items.isNotEmpty) {
    final Object? first = items.first;
    if (first is Map && first['title'] is String) {
      return first['title'] as String;
    }
  }
  return '';
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// What a failed `cancel_order` call means. Same rule as `place_order`: a
/// Postgres answer means nothing changed; no answer means it may have.
CancelResult cancelResultFromError(Object error) {
  if (error is! PostgrestException) return CancelResult.unreachable;
  final String? code = error.code;
  if (code == null || RegExp(r'^\d{3}$').hasMatch(code)) {
    return CancelResult.unreachable;
  }
  return error.message == 'too_late_to_cancel'
      ? CancelResult.tooLate
      : CancelResult.unreachable;
}

/// `cancel_order`'s success answer (`restored` is false on a repeat).
CancelResult cancelResultFrom(Map<String, dynamic> row) =>
    row['restored'] == false
        ? CancelResult.alreadyCancelled
        : CancelResult.cancelled;
