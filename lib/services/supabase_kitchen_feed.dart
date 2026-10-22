import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/kitchen_display/application/kitchen_order_feed.dart';
import '../features/kitchen_display/domain/kitchen_station.dart';
import '../features/kitchen_display/domain/kitchen_ticket.dart';
import 'kitchen_wire.dart';
import 'supabase_service.dart';

/// The board's tickets from Supabase. Needs a staff session (RLS).
///
/// Change events are only a signal: on any change to `orders` or
/// `order_items` it refetches the active board in one query (debounced), so
/// the board is never assembled from a trail of partial events.
final class SupabaseKitchenFeed implements KitchenOrderFeed {
  /// Creates the feed.
  SupabaseKitchenFeed({
    SupabaseClient Function()? client,
    this.debounce = const Duration(milliseconds: 250),
  }) : _client = client ?? (() => SupabaseService.client);

  final SupabaseClient Function() _client;

  /// How long to let a burst of change events settle before refetching.
  final Duration debounce;

  final StreamController<List<KitchenTicket>> _out =
      StreamController<List<KitchenTicket>>.broadcast();
  Map<String, KitchenTicketRef> _refs = <String, KitchenTicketRef>{};
  RealtimeChannel? _channel;
  Timer? _settle;
  int _fetches = 0;

  @override
  Stream<List<KitchenTicket>> watch() {
    _channel ??= _client()
        .channel('kitchen-board')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _schedule(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) => _schedule(),
        )
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
      // (Re)subscribed — possibly after a dropped connection: catch up.
      if (status == RealtimeSubscribeStatus.subscribed) _schedule();
      if (error != null) debugPrint('kitchen realtime: $error');
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
          .select(kitchenOrderColumns)
          .inFilter('status', kitchenActiveStatuses)
          .order('created_at');
      // A later fetch was started while this one was in flight: it wins.
      if (fetch != _fetches || _out.isClosed) return;
      final KitchenSnapshot snapshot = kitchenSnapshotFromRows(rows);
      _refs = snapshot.refs;
      _out.add(snapshot.tickets);
    } catch (error) {
      debugPrint('kitchen refresh failed: $error');
    }
  }

  KitchenTicketRef _ref(String code) {
    final KitchenTicketRef? ref = _refs[code];
    if (ref == null) throw StateError('no ticket $code on the board');
    return ref;
  }

  Future<void> _moveTo(String code, String status) async {
    final KitchenTicketRef ref = _ref(code);
    await _client()
        .from('orders')
        .update(<String, String>{'status': status}).eq('id', ref.orderId);
    _refs[code] = KitchenTicketRef(
      orderId: ref.orderId,
      itemId: ref.itemId,
      status: status,
    );
  }

  @override
  Future<void> setStation(
    String code,
    KitchenStation station, {
    required bool done,
  }) async {
    // The first tap is the kitchen starting the plate. Status only moves
    // forward one step at a time, so PENDING goes through ACCEPTED.
    if (_ref(code).status == 'PENDING') await _moveTo(code, 'ACCEPTED');
    if (_ref(code).status == 'ACCEPTED') await _moveTo(code, 'ASSEMBLING');
    await _client().rpc<Object?>(
      'set_station_status',
      params: <String, Object>{
        'p_item_id': _ref(code).itemId,
        'p_station': station.name,
        'p_done': done,
      },
    );
  }

  @override
  Future<void> markPlated(String code) async {
    if (_ref(code).status == 'ASSEMBLING') await _moveTo(code, 'READY');
  }

  @override
  Future<void> markCollected(String code) async {
    if (_ref(code).status == 'READY') await _moveTo(code, 'COMPLETED');
  }

  @override
  void dispose() {
    _settle?.cancel();
    final RealtimeChannel? channel = _channel;
    if (channel != null) unawaited(_client().removeChannel(channel));
    unawaited(_out.close());
  }
}
