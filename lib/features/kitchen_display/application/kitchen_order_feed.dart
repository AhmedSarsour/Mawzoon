import '../domain/kitchen_station.dart';
import '../domain/kitchen_ticket.dart';

/// Where the board's tickets come from and where its taps go.
///
/// The board stays the authority on *what a tap means* (toggle, plated,
/// archived); the feed only carries tickets in and facts out.
abstract interface class KitchenOrderFeed {
  /// Every active ticket, sent whole on each change, oldest first.
  Stream<List<KitchenTicket>> watch();

  /// Asks for a fresh snapshot now.
  Future<void> refresh();

  /// Records [station] on ticket [code] as done or not done. Sets the value,
  /// never flips it, so a replayed tap can't undo itself.
  Future<void> setStation(
    String code,
    KitchenStation station, {
    required bool done,
  });

  /// Every station on [code] is done: the plate is on the pass.
  Future<void> markPlated(String code);

  /// [code] has left the building.
  Future<void> markCollected(String code);

  /// Stops listening.
  void dispose();
}
