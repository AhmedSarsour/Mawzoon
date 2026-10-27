import '../../../core/pricing/money.dart';

/// An order waiting for its money at the counter.
final class UnpaidOrder {
  /// Creates the view.
  const UnpaidOrder({
    required this.id,
    required this.number,
    required this.total,
    this.dueAt,
    this.createdAt,
    this.title = '',
  });

  /// The server's id.
  final String id;

  /// The number the guest shows.
  final int number;

  /// What the guest owes.
  final Money total;

  /// When it expires (server clock).
  final DateTime? dueAt;

  /// When it was placed.
  final DateTime? createdAt;

  /// The plate.
  final String title;

  /// `M-<number>`.
  String get code => 'M-$number';

  /// Past its deadline. The server decides for real; this only greys the card.
  bool isExpiredAt(DateTime now) => dueAt != null && !now.isBefore(dueAt!);
}

/// The counter's list of unpaid orders.
abstract interface class UnpaidOrderFeed {
  /// Every unpaid order, soonest-to-expire first, sent whole on each change.
  Stream<List<UnpaidOrder>> watch();

  /// Asks for a fresh list now.
  Future<void> refresh();

  /// Stops listening.
  void dispose();
}

/// Orders whose code contains [query] digits (`12` matches `M-12`, `M-112`).
/// Empty or digit-less [query] keeps everything. O(n) per keystroke; n is the
/// handful of orders waiting at once.
List<UnpaidOrder> searchByNumber(List<UnpaidOrder> orders, String query) {
  final String digits = query.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return orders;
  return orders
      .where((UnpaidOrder o) => o.number.toString().contains(digits))
      .toList();
}
