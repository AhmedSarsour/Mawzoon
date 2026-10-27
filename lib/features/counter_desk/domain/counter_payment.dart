/// What happened when the cashier tapped "paid" on an order.
enum CounterPayResult {
  /// Money taken: the order went to the kitchen.
  paid,

  /// Someone already marked it paid (double tap, second cashier). Nothing changed.
  alreadyPaid,

  /// Past its deadline: the guest must order again.
  expired,

  /// The guest or staff cancelled it.
  cancelled,

  /// A delivery order: paid by card only, never at the counter.
  cardRequired,

  /// No such order (or the session isn't staff).
  notFound,

  /// No answer from the server: unknown whether it was marked. Tapping again
  /// is safe — a second mark is [alreadyPaid].
  unreachable,
}

/// Paying an order at the counter.
abstract interface class CounterDesk {
  /// Marks [orderId] paid in cash or by the counter's card machine.
  Future<CounterPayResult> markPaid(String orderId);
}
