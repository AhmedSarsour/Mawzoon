import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/counter_payment.dart';
import '../domain/unpaid_order.dart';

/// What the cashier last learned from a "paid" tap.
final class CounterNotice {
  /// Creates a notice.
  const CounterNotice(this.code, this.result);

  /// The order it was about (`M-12`).
  final String code;

  /// What the server said.
  final CounterPayResult result;
}

/// The counter's state: the unpaid list, the search box, and the one card
/// asking "did you take the money?".
///
/// A tap on "paid" first asks (one extra tap beats marking the wrong order:
/// a paid order goes straight to the cooks and can't be pulled back).
class CounterController extends ChangeNotifier {
  /// Creates the controller. [clock] is injectable for tests.
  CounterController({
    required UnpaidOrderFeed feed,
    required CounterDesk desk,
    DateTime Function()? clock,
    this.noticeFor = const Duration(seconds: 6),
    this.tick = const Duration(seconds: 20),
  })  : _feed = feed,
        _desk = desk,
        _clock = clock ?? DateTime.now;

  final UnpaidOrderFeed _feed;
  final CounterDesk _desk;
  final DateTime Function() _clock;

  /// How long a result stays on screen.
  final Duration noticeFor;

  /// How often ages and "expires in" labels refresh.
  final Duration tick;

  StreamSubscription<List<UnpaidOrder>>? _sub;
  Timer? _ticker;
  Timer? _noticeTimer;
  List<UnpaidOrder> _all = const <UnpaidOrder>[];
  String _query = '';
  String? _confirming;
  String? _busy;
  CounterNotice? _notice;
  bool _loaded = false;

  /// Orders matching the search box, soonest to expire first.
  List<UnpaidOrder> get orders => searchByNumber(_all, _query);

  /// Whether the first list has arrived.
  bool get loaded => _loaded;

  /// The search text.
  String get query => _query;

  /// The order whose card is asking for confirmation.
  String? get confirmingId => _confirming;

  /// The order being marked right now.
  String? get busyId => _busy;

  /// The last result, for a few seconds.
  CounterNotice? get notice => _notice;

  /// Now, by the injected clock.
  DateTime get now => _clock();

  /// Starts listening.
  void start() {
    _sub = _feed.watch().listen((List<UnpaidOrder> next) {
      _all = next;
      _loaded = true;
      // A confirmation for an order that left the list (paid by someone else,
      // swept) has nothing to confirm.
      if (_confirming != null &&
          !next.any((UnpaidOrder o) => o.id == _confirming)) {
        _confirming = null;
      }
      notifyListeners();
    });
    _ticker = Timer.periodic(tick, (_) => notifyListeners());
  }

  /// Filters the list by order number.
  void setQuery(String text) {
    if (text == _query) return;
    _query = text;
    notifyListeners();
  }

  /// Opens the "did you take the money?" question on [id].
  void ask(String id) {
    if (_busy != null) return;
    _confirming = id;
    _notice = null;
    notifyListeners();
  }

  /// Closes the question without marking anything.
  void back() {
    _confirming = null;
    notifyListeners();
  }

  /// The cashier said yes: marks [order] paid and handles every answer.
  Future<void> confirm(UnpaidOrder order) async {
    if (_busy != null) return;
    _busy = order.id;
    notifyListeners();
    final CounterPayResult result = await _desk.markPaid(order.id);
    _busy = null;
    // No answer: unknown whether it went through. Keep the question open;
    // tapping yes again is safe (a second mark is "already paid").
    if (result != CounterPayResult.unreachable) _confirming = null;
    _showNotice(CounterNotice(order.code, result));
    if (result != CounterPayResult.unreachable) {
      unawaited(_feed.refresh());
    }
  }

  void _showNotice(CounterNotice notice) {
    _notice = notice;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(noticeFor, () {
      _notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _ticker?.cancel();
    _noticeTimer?.cancel();
    _feed.dispose();
    super.dispose();
  }
}
