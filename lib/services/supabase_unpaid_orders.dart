import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/counter_desk/domain/unpaid_order.dart';
import 'supabase_service.dart';
import 'tracking_wire.dart';

/// The counter's unpaid orders. Needs a staff session (RLS).
///
/// Realtime is only a refetch signal, like `SupabaseKitchenFeed`. Delivery
/// orders are left out: they are card-only and can't be paid at the till.
final class SupabaseUnpaidOrders implements UnpaidOrderFeed {
  /// Creates the feed.
  SupabaseUnpaidOrders({
    SupabaseClient Function()? client,
    this.debounce = const Duration(milliseconds: 250),
  }) : _client = client ?? (() => SupabaseService.client);

  final SupabaseClient Function() _client;

  /// How long to let a burst of change events settle before refetching.
  final Duration debounce;

  final StreamController<List<UnpaidOrder>> _out =
      StreamController<List<UnpaidOrder>>.broadcast();
  RealtimeChannel? _channel;
  Timer? _settle;
  int _fetches = 0;

  @override
  Stream<List<UnpaidOrder>> watch() {
    _channel ??= _client()
        .channel('counter-unpaid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _schedule(),
        )
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
      if (status == RealtimeSubscribeStatus.subscribed) _schedule();
      if (error != null) debugPrint('counter realtime: $error');
    });
    unawaited(refresh());
    return _out.stream;
  }

  void _schedule() {
    _settle?.cancel();
    _settle = Timer(debounce, () => unawaited(refresh()));
  }

  @override
  Future<void> refresh() async {
    final int fetch = ++_fetches;
    try {
      final List<dynamic> rows = await _client()
          .from('orders')
          .select(unpaidOrderColumns)
          .eq('status', 'AWAITING_PAYMENT')
          .neq('order_type', 'DELIVERY')
          .order('payment_due_at');
      if (fetch != _fetches || _out.isClosed) return;
      _out.add(<UnpaidOrder>[
        for (final dynamic r in rows)
          unpaidOrderFromRow(r as Map<String, dynamic>),
      ]);
    } catch (error) {
      debugPrint('counter refresh failed: $error');
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    final RealtimeChannel? channel = _channel;
    if (channel != null) unawaited(_client().removeChannel(channel));
    unawaited(_out.close());
  }
}
