import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/features/counter_desk/domain/counter_payment.dart';
import 'package:mawzoon/services/counter_wire.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

PostgrestException _pg(String message, {String code = 'P0001'}) =>
    PostgrestException(message: message, code: code);

void main() {
  test('a first tap pays; a second reads already paid', () {
    expect(
      counterPayResultFrom(<String, dynamic>{
        'status': 'PENDING',
        'already_paid': false,
      }),
      CounterPayResult.paid,
    );
    expect(
      counterPayResultFrom(<String, dynamic>{
        'status': 'ACCEPTED',
        'already_paid': true,
      }),
      CounterPayResult.alreadyPaid,
    );
  });

  test('each server key maps to its result', () {
    expect(
      counterPayResultFromError(_pg('order_expired')),
      CounterPayResult.expired,
    );
    expect(
      counterPayResultFromError(_pg('order_cancelled')),
      CounterPayResult.cancelled,
    );
    expect(
      counterPayResultFromError(_pg('card_required')),
      CounterPayResult.cardRequired,
    );
    expect(
      counterPayResultFromError(_pg('not_found')),
      CounterPayResult.notFound,
    );
    expect(
      counterPayResultFromError(_pg('staff only', code: '42501')),
      CounterPayResult.notFound,
    );
  });

  test('no answer is unreachable, never "paid"', () {
    expect(
      counterPayResultFromError(const SocketException('down')),
      CounterPayResult.unreachable,
    );
    expect(
      counterPayResultFromError(TimeoutException('slow')),
      CounterPayResult.unreachable,
    );
    expect(
      counterPayResultFromError(_pg('Bad Gateway', code: '502')),
      CounterPayResult.unreachable,
    );
  });
}
