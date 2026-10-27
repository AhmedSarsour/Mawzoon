import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/order_tracking/domain/tracked_order.dart';
import 'supabase_service.dart';
import 'tracking_wire.dart';

/// The guest's own orders from Supabase (RLS: a guest reads only theirs).
///
/// Same pattern as `SupabaseKitchenFeed`: a change event is only a signal to
/// refetch the row, never trusted as data.
final class SupabaseOrderTracker implements OrderTracker {
  /// Creates the tracker. The client is resolved on each call.
  SupabaseOrderTracker({
    SupabaseClient Function()? client,
    Future<bool> Function()? ensureSession,
    this.timeout = const Duration(seconds: 15),
    this.debounce = const Duration(milliseconds: 250),
  })  : _client = client ?? (() => SupabaseService.client),
        _ensureSession = ensureSession ?? SupabaseService.ensureSession;

  final SupabaseClient Function() _client;
  final Future<bool> Function() _ensureSession;

  /// How long to wait before treating the server as unreachable.
  final Duration timeout;

  /// How long to let a burst of change events settle before refetching.
  final Duration debounce;

  @override
  Stream<TrackedOrder?> watch(String orderId) {
    RealtimeChannel? channel;
    Timer? settle;
    int fetches = 0;
    late final StreamController<TrackedOrder?> out;

    Future<void> refetch() async {
      final int fetch = ++fetches;
      try {
        final Map<String, dynamic>? row = await _client()
            .from('orders')
            .select(trackedOrderColumns)
            .eq('id', orderId)
            .maybeSingle()
            .timeout(timeout);
        // A later fetch started while this one was in flight: it wins.
        if (fetch != fetches || out.isClosed) return;
        out.add(row == null ? null : trackedOrderFromRow(row));
      } catch (error) {
        debugPrint('order refresh failed: $error');
      }
    }

    void schedule() {
      settle?.cancel();
      settle = Timer(debounce, () => unawaited(refetch()));
    }

    out = StreamController<TrackedOrder?>(
      onListen: () {
        channel = _client()
            .channel('order-$orderId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'orders',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: orderId,
              ),
              callback: (_) => schedule(),
            )
            .subscribe((RealtimeSubscribeStatus status, Object? error) {
          // (Re)subscribed — possibly after a dropped connection: catch up.
          if (status == RealtimeSubscribeStatus.subscribed) schedule();
          if (error != null) debugPrint('order realtime: $error');
        });
        unawaited(refetch());
      },
      onCancel: () {
        settle?.cancel();
        final RealtimeChannel? c = channel;
        if (c != null) unawaited(_client().removeChannel(c));
      },
    );
    return out.stream;
  }

  @override
  Future<TrackedOrder?> openOrder() async {
    if (!await _ensureSession()) return null;
    try {
      final List<dynamic> rows = await _client()
          .from('orders')
          .select(trackedOrderColumns)
          .inFilter('status', openOrderStatuses)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(timeout);
      if (rows.isEmpty) return null;
      return trackedOrderFromRow(rows.first as Map<String, dynamic>);
    } catch (error) {
      debugPrint('open order lookup failed: $error');
      return null;
    }
  }

  @override
  Future<CancelResult> cancel(String orderId) async {
    try {
      final Object? data = await _client().rpc<Object?>(
        'cancel_order',
        params: <String, Object?>{'p_order_id': orderId},
      ).timeout(timeout);
      return cancelResultFrom(data! as Map<String, dynamic>);
    } catch (error) {
      debugPrint('cancel_order failed: $error');
      return cancelResultFromError(error);
    }
  }
}
