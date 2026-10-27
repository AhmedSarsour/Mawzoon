import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/counter_desk/domain/counter_payment.dart';
import 'counter_wire.dart';
import 'supabase_service.dart';

/// Marks orders paid through `mark_paid_counter`. Needs a staff session.
final class SupabaseCounterDesk implements CounterDesk {
  /// Creates the desk. The client is resolved on each call, not captured.
  SupabaseCounterDesk({
    SupabaseClient Function()? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? (() => SupabaseService.client);

  final SupabaseClient Function() _client;

  /// How long to wait before treating the server as unreachable.
  final Duration timeout;

  @override
  Future<CounterPayResult> markPaid(String orderId) async {
    try {
      final Object? data = await _client().rpc<Object?>(
        'mark_paid_counter',
        params: <String, Object?>{'p_order_id': orderId},
      ).timeout(timeout);
      return counterPayResultFrom(data! as Map<String, dynamic>);
    } catch (error) {
      debugPrint('mark_paid_counter failed: $error');
      return counterPayResultFromError(error);
    }
  }
}
