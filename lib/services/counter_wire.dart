import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../features/counter_desk/domain/counter_payment.dart';

// How `mark_paid_counter` answers read in the app
// (supabase/migrations/20261022140000_module12_payment_state.sql). Pure.

/// `mark_paid_counter`'s success answer.
CounterPayResult counterPayResultFrom(Map<String, dynamic> row) =>
    row['already_paid'] == true
        ? CounterPayResult.alreadyPaid
        : CounterPayResult.paid;

/// What a failed `mark_paid_counter` call means at the till.
///
/// Same rule as `outcomeFromError`: a Postgres answer means nothing changed;
/// no answer means it may have, and tapping again is safe.
CounterPayResult counterPayResultFromError(Object error) {
  if (error is! PostgrestException) return CounterPayResult.unreachable;
  final String? code = error.code;
  if (code == null || RegExp(r'^\d{3}$').hasMatch(code)) {
    return CounterPayResult.unreachable;
  }
  return switch (error.message) {
    'order_expired' => CounterPayResult.expired,
    'order_cancelled' => CounterPayResult.cancelled,
    'card_required' => CounterPayResult.cardRequired,
    _ => CounterPayResult.notFound,
  };
}
