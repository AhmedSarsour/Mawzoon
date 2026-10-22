import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/menu/catalogue_fingerprint.g.dart';
import '../features/cart_checkout/domain/order_draft.dart';
import '../features/cart_checkout/domain/order_placement.dart';
import 'order_wire.dart';
import 'supabase_service.dart';

/// Places orders through the `place_order` function.
final class SupabaseOrderGateway implements OrderGateway {
  /// Creates the gateway. The client is resolved on each call, not captured,
  /// so a gateway built before Supabase starts still works once it has.
  SupabaseOrderGateway({
    SupabaseClient Function()? client,
    Future<bool> Function()? ensureSession,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? (() => SupabaseService.client),
        _ensureSession = ensureSession ?? SupabaseService.ensureSession;

  final SupabaseClient Function() _client;
  final Future<bool> Function() _ensureSession;

  /// How long to wait before treating the server as unreachable.
  final Duration timeout;

  @override
  Future<PlaceOrderOutcome> place(
    OrderDraft draft, {
    required String idempotencyKey,
  }) async {
    if (!await _ensureSession()) return const OrderUnreachable();
    try {
      final Object? data = await _client().rpc<Object?>(
        'place_order',
        params: <String, Object?>{
          'p_order': placeOrderPayload(draft),
          'p_idempotency_key': idempotencyKey,
          'p_catalogue_fingerprint': catalogueFingerprint,
        },
      ).timeout(timeout);
      return orderPlacedFrom(data! as Map<String, dynamic>);
    } catch (error) {
      debugPrint('place_order failed: $error');
      return outcomeFromError(error);
    }
  }
}
