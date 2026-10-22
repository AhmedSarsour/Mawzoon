import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/manager_suite/application/back_office_store.dart';
import '../features/manager_suite/domain/inventory_ledger.dart';
import 'supabase_service.dart';

/// The back office on Supabase. Needs a staff session (RLS).
final class SupabaseBackOffice implements BackOfficeStore {
  /// Creates the store.
  SupabaseBackOffice({
    SupabaseClient Function()? client,
    this.debounce = const Duration(milliseconds: 400),
  }) : _client = client ?? (() => SupabaseService.client);

  final SupabaseClient Function() _client;

  /// How long a burst of change events (a busy service) settles before one
  /// reload.
  final Duration debounce;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  RealtimeChannel? _channel;
  Timer? _settle;

  @override
  Future<BackOfficeSnapshot> load() async {
    final SupabaseClient client = _client();
    final List<dynamic> stock =
        await client.from('raw_ingredients').select('id, stock_minor_units');
    final List<dynamic> off = await client
        .from('component_settings')
        .select('component_id')
        .eq('forced_off', true);
    final Map<String, dynamic> rails = await client
        .from('stock_rails')
        .select('safety_buffer_portions, low_water_mark_portions')
        .single();
    return BackOfficeSnapshot(
      stockMinorUnits: <String, int>{
        for (final Map<String, dynamic> r in stock.cast<Map<String, dynamic>>())
          r['id'] as String: (r['stock_minor_units'] as num).toInt(),
      },
      forcedOff: <String>{
        for (final Map<String, dynamic> r in off.cast<Map<String, dynamic>>())
          r['component_id'] as String,
      },
      rails: StockRails(
        safetyBuffer: (rails['safety_buffer_portions'] as num).toInt(),
        lowWaterMark: (rails['low_water_mark_portions'] as num).toInt(),
      ),
    );
  }

  @override
  Stream<void> changes() {
    _channel ??= _client()
        .channel('back-office')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'raw_ingredients',
          callback: (_) => _ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'component_settings',
          callback: (_) => _ping(),
        )
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
      if (status == RealtimeSubscribeStatus.subscribed) _ping();
      if (error != null) debugPrint('back-office realtime: $error');
    });
    return _changes.stream;
  }

  void _ping() {
    _settle?.cancel();
    _settle = Timer(debounce, () {
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  @override
  Future<void> setCount(String ingredientId, int minorUnits) =>
      _client().rpc<Object?>(
        'set_stock_count',
        params: <String, Object>{
          'p_ingredient': ingredientId,
          'p_amount_minor_units': minorUnits,
        },
      );

  @override
  Future<void> adjust(String ingredientId, int deltaMinorUnits) =>
      _client().rpc<Object?>(
        'adjust_stock',
        params: <String, Object>{
          'p_ingredient': ingredientId,
          'p_delta_minor_units': deltaMinorUnits,
        },
      );

  @override
  Future<void> setForcedOff(String componentId, {required bool off}) =>
      _client().from('component_settings').upsert(<String, Object>{
        'component_id': componentId,
        'forced_off': off,
      });

  @override
  Future<void> setPortionFactor(String componentId, double factor) =>
      _client().from('component_settings').upsert(<String, Object>{
        'component_id': componentId,
        // numeric(6,3) on the server.
        'portion_factor': (factor * 1000).round() / 1000,
      });

  @override
  void dispose() {
    _settle?.cancel();
    final RealtimeChannel? channel = _channel;
    if (channel != null) unawaited(_client().removeChannel(channel));
    unawaited(_changes.close());
  }
}
