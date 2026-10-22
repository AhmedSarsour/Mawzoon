import '../domain/inventory_ledger.dart';

/// The back office as the server last saw it.
final class BackOfficeSnapshot {
  /// Creates a snapshot.
  const BackOfficeSnapshot({
    required this.stockMinorUnits,
    required this.forcedOff,
    required this.rails,
  });

  /// Book stock per ingredient id, in thousandths of the ingredient's unit.
  final Map<String, int> stockMinorUnits;

  /// Components a manager has taken off by hand.
  final Set<String> forcedOff;

  /// The site's selling rails.
  final StockRails rails;
}

/// Where the back office's counts and switches are kept.
abstract interface class BackOfficeStore {
  /// The current state.
  Future<BackOfficeSnapshot> load();

  /// Fires when something changed on the server — an order drew stock, or
  /// another tablet recorded a count.
  Stream<void> changes();

  /// A stock take: the book becomes exactly [minorUnits].
  Future<void> setCount(String ingredientId, int minorUnits);

  /// A delivery (positive) or a write-off (negative).
  Future<void> adjust(String ingredientId, int deltaMinorUnits);

  /// Takes [componentId] off the menu, or puts it back.
  Future<void> setForcedOff(String componentId, {required bool off});

  /// The portion calibration the server's stock draws use for [componentId].
  Future<void> setPortionFactor(String componentId, double factor);

  /// Stops listening.
  void dispose();
}
