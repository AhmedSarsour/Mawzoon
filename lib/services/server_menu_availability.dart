import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/menu/stock_status.dart';
import 'order_wire.dart';
import 'supabase_service.dart';

/// What the guest app may sell, as the server last said.
///
/// Polled, not streamed: guests can't subscribe to the stock tables (RLS keeps
/// counts back-office only), and a menu a few seconds stale is safe because
/// `place_order` re-checks under a lock. Starts as "everything" so the first
/// frame isn't a wall of sold-out dishes while the first answer is in flight.
final class ServerMenuAvailability extends ValueNotifier<MenuAvailability> {
  /// Creates the feed. Call [start] to begin polling.
  ServerMenuAvailability({
    SupabaseClient Function()? client,
    Future<bool> Function()? ensureSession,
    this.interval = const Duration(seconds: 30),
  })  : _client = client ?? (() => SupabaseService.client),
        _ensureSession = ensureSession ?? SupabaseService.ensureSession,
        super(MenuAvailability.everything);

  final SupabaseClient Function() _client;
  final Future<bool> Function() _ensureSession;

  /// How often to ask.
  final Duration interval;

  Timer? _timer;
  bool _disposed = false;

  /// Fetches now, then every [interval].
  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  /// Fetches now. On failure the last answer stands.
  Future<void> refresh() async {
    try {
      if (!await _ensureSession()) return;
      final List<dynamic> rows =
          await _client().rpc<List<dynamic>>('menu_availability');
      if (!_disposed) value = availabilityFromRows(rows);
    } catch (error) {
      debugPrint('menu_availability failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
