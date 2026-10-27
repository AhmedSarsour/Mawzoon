import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/pricing/money.dart';
import 'package:mawzoon/features/order_tracking/domain/tracked_order.dart';
import 'package:mawzoon/services/tracking_wire.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _row({String status = 'AWAITING_PAYMENT'}) =>
    <String, dynamic>{
      'id': 'o-1',
      'order_number': 12,
      'order_type': 'PICKUP',
      'status': status,
      'total_price_minor_units': 4900,
      'payment_due_at': '2026-10-22T19:45:00Z',
      'cancel_reason': null,
      'created_at': '2026-10-22T19:00:00Z',
      'order_items': <Map<String, String>>[
        <String, String>{'title': 'صحن موزون'},
      ],
    };

void main() {
  group('stageFromStatus', () {
    test('each status reads as the guest\'s stage', () {
      expect(stageFromStatus('AWAITING_PAYMENT'), OrderStage.awaitingPayment);
      expect(stageFromStatus('PENDING'), OrderStage.paid);
      expect(stageFromStatus('ACCEPTED'), OrderStage.paid);
      expect(stageFromStatus('ASSEMBLING'), OrderStage.making);
      expect(stageFromStatus('READY'), OrderStage.ready);
      expect(stageFromStatus('COMPLETED'), OrderStage.done);
      expect(stageFromStatus('CANCELLED'), OrderStage.cancelled);
    });

    test('an unknown status never reads as "pay now"', () {
      expect(stageFromStatus('SOMETHING_NEW'), OrderStage.paid);
      expect(stageFromStatus(null), OrderStage.paid);
    });
  });

  group('trackedOrderFromRow', () {
    test('reads the number, total, server deadline and plate', () {
      final TrackedOrder o = trackedOrderFromRow(_row());
      expect(o.code, 'M-12');
      expect(o.total, const Money(4900));
      expect(o.dueAt, DateTime.utc(2026, 10, 22, 19, 45));
      expect(o.title, 'صحن موزون');
      expect(o.stage, OrderStage.awaitingPayment);
    });

    test('an expired cancel carries its reason', () {
      final Map<String, dynamic> row = _row(status: 'CANCELLED')
        ..['cancel_reason'] = 'expired';
      expect(trackedOrderFromRow(row).cancelReason, CancelReason.expired);
    });
  });

  test('unpaidOrderFromRow reads the counter\'s card', () {
    final order = unpaidOrderFromRow(_row());
    expect(order.code, 'M-12');
    expect(order.total, const Money(4900));
    expect(order.createdAt, DateTime.utc(2026, 10, 22, 19));
  });

  group('cancel answers', () {
    test('success and repeat', () {
      expect(
        cancelResultFrom(<String, dynamic>{'restored': true}),
        CancelResult.cancelled,
      );
      expect(
        cancelResultFrom(<String, dynamic>{'restored': false}),
        CancelResult.alreadyCancelled,
      );
    });

    test('too_late_to_cancel means paid; no answer means unknown', () {
      expect(
        cancelResultFromError(
          const PostgrestException(
            message: 'too_late_to_cancel',
            code: 'P0001',
          ),
        ),
        CancelResult.tooLate,
      );
      expect(
        cancelResultFromError(Exception('offline')),
        CancelResult.unreachable,
      );
      expect(
        cancelResultFromError(
          const PostgrestException(message: 'x', code: '503'),
        ),
        CancelResult.unreachable,
      );
    });
  });

  group('labels', () {
    test('clockTime uses Western digits, zero padded', () {
      expect(clockTime(DateTime(2026, 10, 22, 9, 5)), '09:05');
    });

    test('ages and expiry stay short and need no counted noun', () {
      expect(ageLabel(const Duration(seconds: 20), arabic: true), 'الآن');
      expect(ageLabel(const Duration(minutes: 12), arabic: true), 'قبل 12 د');
      expect(
        expiresInLabel(const Duration(minutes: 6, seconds: 1), arabic: true),
        'ينتهي بعد 7 د',
      );
      expect(expiresInLabel(Duration.zero, arabic: true), isNull);
    });
  });
}
