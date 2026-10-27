import '../../../core/pricing/money.dart';

/// Where a guest's order stands, in the words the guest cares about.
///
/// [awaitingPayment] is the only stage in which the kitchen does NOT have the
/// order — guest copy for it must never say otherwise.
enum OrderStage {
  /// Placed, not paid: invisible to the cooks until the counter or card pays.
  awaitingPayment,

  /// Paid, waiting for a cook to start (`PENDING`, `ACCEPTED`).
  paid,

  /// On the line (`ASSEMBLING`).
  making,

  /// On the pass (`READY`).
  ready,

  /// Collected or delivered (`COMPLETED`).
  done,

  /// Cancelled by the guest, staff, or the expiry sweep.
  cancelled;

  /// Whether the guest still has something to do or wait for.
  bool get isOpen => this != done && this != cancelled;
}

/// Why a cancelled order was cancelled (`orders.cancel_reason`).
enum CancelReason {
  /// The guest cancelled it.
  guest,

  /// Staff cancelled it.
  staff,

  /// Nobody paid before the deadline.
  expired,
}

/// One order as its owner sees it. Read from the `orders` row.
final class TrackedOrder {
  /// Creates the view.
  const TrackedOrder({
    required this.id,
    required this.number,
    required this.stage,
    required this.total,
    this.dueAt,
    this.cancelReason,
    this.title = '',
    this.isDelivery = false,
  });

  /// The server's id.
  final String id;

  /// The number called at the pass.
  final int number;

  /// Where it stands.
  final OrderStage stage;

  /// What the server charged.
  final Money total;

  /// When an unpaid order expires (server clock), else null.
  final DateTime? dueAt;

  /// Set when [stage] is [OrderStage.cancelled].
  final CancelReason? cancelReason;

  /// The plate, as the kitchen reads it.
  final String title;

  /// Whether it goes out for delivery.
  final bool isDelivery;

  /// `M-<number>`.
  String get code => 'M-$number';

  /// This order with a different [stage] — the optimistic step after a cancel.
  TrackedOrder withStage(OrderStage next, {CancelReason? reason}) =>
      TrackedOrder(
        id: id,
        number: number,
        stage: next,
        total: total,
        dueAt: dueAt,
        cancelReason: reason ?? cancelReason,
        title: title,
        isDelivery: isDelivery,
      );
}

/// What happened when the guest tapped "cancel".
enum CancelResult {
  /// Cancelled; the portions are back on sale.
  cancelled,

  /// It was already cancelled (expired a moment ago, or a double tap).
  alreadyCancelled,

  /// Paid already: only staff can cancel now (`too_late_to_cancel`).
  tooLate,

  /// No answer: unknown whether it went through. Tapping again is safe.
  unreachable,
}

/// A guest's window onto their own orders.
abstract interface class OrderTracker {
  /// The order now, then again on every change. Emits null if it can't be
  /// read (not yours, or missing).
  Stream<TrackedOrder?> watch(String orderId);

  /// The guest's open order, if any — for reopening the app.
  Future<TrackedOrder?> openOrder();

  /// Cancels an unpaid order.
  Future<CancelResult> cancel(String orderId);
}

/// `19:45` — a wall-clock time in Western digits, in the phone's time zone.
String clockTime(DateTime at) {
  final DateTime local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// How long ago, as a short label: `الآن` / `قبل 5 د` (en: `now` / `5 min ago`).
/// Abbreviated so Arabic needs no counted-noun agreement.
String ageLabel(Duration age, {required bool arabic}) {
  final int minutes = age.inMinutes < 0 ? 0 : age.inMinutes;
  if (minutes < 1) return arabic ? 'الآن' : 'now';
  return arabic ? 'قبل $minutes د' : '$minutes min ago';
}

/// `ينتهي بعد 7 د` (en: `expires in 7 min`); null when already past.
String? expiresInLabel(Duration left, {required bool arabic}) {
  if (left <= Duration.zero) return null;
  final int minutes = (left.inSeconds / 60).ceil();
  return arabic ? 'ينتهي بعد $minutes د' : 'expires in $minutes min';
}
