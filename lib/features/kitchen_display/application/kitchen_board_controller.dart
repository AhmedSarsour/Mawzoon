import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/kitchen_station.dart';
import '../domain/kitchen_ticket.dart';
import 'kitchen_order_feed.dart';

/// What the pass hears when a ticket is finished.
///
/// Behind an interface because a kitchen chime is a property of the room, not
/// of the app: one site wants a bell over the noise of a fryer, another runs
/// silent after 10pm, and a test wants neither.
abstract interface class KitchenChime {
  /// Sounds the completion chime.
  void ring();
}

/// The default chime: the platform's own alert tone.
///
/// A placeholder, honestly labelled. A real install should replace this with a
/// short bundled sample chosen to cut through a working kitchen — the system
/// alert is audible on a quiet tablet and useless beside an extractor hood.
final class SystemKitchenChime implements KitchenChime {
  /// Creates the default chime.
  const SystemKitchenChime();

  @override
  void ring() {
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.mediumImpact());
  }
}

/// A chime that does nothing, for a silent service or a test.
final class SilentChime implements KitchenChime {
  /// Creates a silent chime.
  const SilentChime();

  @override
  void ring() {}
}

/// Drives the kitchen board.
///
/// Holds the live line and the packaging queue, and owns the one clock the
/// board needs. Urgency changes with time rather than with input, so something
/// has to tick — but a badge that crosses a threshold a few seconds late costs
/// nothing, and repainting a tablet at 60Hz all service costs a great deal.
/// [clockInterval] is therefore seconds, not frames.
final class KitchenBoardController extends ChangeNotifier {
  /// Creates a board.
  ///
  /// With a [feed], tickets come from it and every tap is written back to it;
  /// without one, the board is filled by [receive] (tests, a demo tablet).
  KitchenBoardController({
    KitchenChime chime = const SystemKitchenChime(),
    this.clockInterval = const Duration(seconds: 10),
    DateTime Function()? now,
    KitchenOrderFeed? feed,
  })  : _chime = chime,
        _now = now ?? DateTime.now,
        _feed = feed {
    _timer = Timer.periodic(clockInterval, (_) => _onClock());
    _subscription = feed?.watch().listen(_onSnapshot);
  }

  final KitchenOrderFeed? _feed;
  StreamSubscription<List<KitchenTicket>>? _subscription;

  /// Writes still on their way to the feed. A snapshot read before they land
  /// would briefly undo the cook's tap, so snapshots arriving meanwhile are
  /// dropped and one fresh snapshot is fetched once they settle.
  int _writesInFlight = 0;

  /// Tickets already repaired once (see [_onSnapshot]); never retried in a
  /// loop.
  final Set<String> _repaired = <String>{};

  /// How often the urgency badges are re-evaluated.
  final Duration clockInterval;

  final KitchenChime _chime;
  final DateTime Function() _now;
  Timer? _timer;
  bool _disposed = false;

  final List<KitchenTicket> _line = <KitchenTicket>[];
  final List<KitchenTicket> _packaging = <KitchenTicket>[];

  /// Tickets still being assembled, oldest first — which is the order the line
  /// should work in, so the board never has to be re-sorted by eye.
  List<KitchenTicket> get line => List<KitchenTicket>.unmodifiable(_line);

  /// Finished tickets waiting to be packed, most recent first.
  List<KitchenTicket> get packaging =>
      List<KitchenTicket>.unmodifiable(_packaging);

  /// The board's current time, injectable so urgency is testable.
  DateTime get now => _now();

  /// Puts a ticket on the line.
  void receive(KitchenTicket ticket) {
    if (_disposed) return;
    _line
      ..add(ticket)
      ..sort(
        (KitchenTicket a, KitchenTicket b) => a.placedAt.compareTo(b.placedAt),
      );
    notifyListeners();
  }

  /// Marks a station finished, or unmarks it.
  ///
  /// When the tap completes the plate, the ticket archives itself and the
  /// chime rings. Auto-archiving is deliberate: asking a cook with full hands
  /// to tap a fourth time to confirm what the board can already see is how
  /// finished tickets sit on a board until someone tidies up.
  void toggleStation(String code, KitchenStation station) {
    if (_disposed) return;
    final int index = _line.indexWhere((KitchenTicket t) => t.code == code);
    if (index < 0) return;

    final KitchenTicket updated = _line[index].toggle(station);
    _writeStation(updated, station);
    if (!updated.status.isPlated) {
      _line[index] = updated;
      notifyListeners();
      return;
    }

    _line.removeAt(index);
    _packaging.insert(0, updated.archive());
    _chime.ring();
    notifyListeners();
  }

  /// Removes a packed ticket from the queue.
  void clearPackaged(String code) {
    if (_disposed) return;
    _packaging.removeWhere((KitchenTicket t) => t.code == code);
    notifyListeners();
    final KitchenOrderFeed? feed = _feed;
    if (feed != null) _write(() => feed.markCollected(code));
  }

  void _writeStation(KitchenTicket updated, KitchenStation station) {
    final KitchenOrderFeed? feed = _feed;
    if (feed == null) return;
    _write(() async {
      await feed.setStation(
        updated.code,
        station,
        done: updated.isPrepped(station),
      );
      if (updated.status.isPlated) await feed.markPlated(updated.code);
    });
  }

  /// Runs one write. On failure the server's view wins: the next snapshot
  /// puts the board back to what was actually saved.
  void _write(Future<void> Function() write) {
    _writesInFlight++;
    unawaited(() async {
      try {
        await write();
      } catch (error) {
        debugPrint('kitchen write failed: $error');
      } finally {
        _writesInFlight--;
        if (_writesInFlight == 0 && !_disposed) await _feed?.refresh();
      }
    }());
  }

  void _onSnapshot(List<KitchenTicket> tickets) {
    if (_disposed) return;
    if (_writesInFlight > 0) return;
    _line
      ..clear()
      ..addAll(tickets.where((KitchenTicket t) => !t.status.isArchived));
    _packaging
      ..clear()
      ..addAll(
        tickets.where((KitchenTicket t) => t.status.isArchived).toList().reversed,
      );
    // All three stations saved but the plated step didn't land (a dropped
    // write): finish it rather than leave a done plate stuck on the line.
    for (final KitchenTicket t in _line.where((KitchenTicket t) => t.status.isPlated)) {
      if (!_repaired.add(t.code)) continue;
      final KitchenOrderFeed feed = _feed!;
      _write(() => feed.markPlated(t.code));
    }
    notifyListeners();
  }

  /// Re-evaluates urgency. Called by the clock, and by tests directly.
  @visibleForTesting
  void tick() => _onClock();

  void _onClock() {
    if (_disposed || _line.isEmpty) return;
    // Nothing on the tickets changes — only their age — so this is a repaint
    // request, not a mutation.
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    _feed?.dispose();
    super.dispose();
  }
}
