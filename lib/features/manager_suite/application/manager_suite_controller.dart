import 'package:flutter/foundation.dart';

import '../../../core/measure/quantity.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../cart_checkout/domain/order_draft.dart';
import '../domain/inventory_ledger.dart';
import '../domain/raw_ingredient.dart';
import '../../../core/menu/recipe_book.dart';
import '../../../core/menu/recipe_calibration.dart';
import '../../../core/menu/stock_status.dart';

/// The back office, as one object.
///
/// ## Why the two halves live together
///
/// Recipe calibration and inventory look like separate concerns and are not.
/// Measuring a portion 10% heavier changes what every future order draws from
/// the store, which changes how many portions are left, which changes what the
/// menu will sell. Splitting them into two controllers means two sources of
/// truth that have to be kept in step by hand, and the first thing that goes
/// out of step is the number a guest is shown.
///
/// The controller holds the [RecipeBook] and the [InventoryLedger] and derives
/// a [MenuAvailability] from both. Nothing else recomputes availability.
final class ManagerSuiteController extends ChangeNotifier {
  /// Creates the suite.
  ManagerSuiteController({
    RecipeBook book = RecipeBook.published,
    InventoryLedger? ledger,
    DateTime Function()? now,
    String signedInAs = 'manager',
  })  : _book = book,
        _ledger = ledger ?? InventoryLedger(),
        _now = now ?? DateTime.now,
        _signedInAs = signedInAs {
    _availability = _ledger.availabilityWith(_book);
  }

  final DateTime Function() _now;
  final String _signedInAs;

  RecipeBook _book;
  InventoryLedger _ledger;
  late MenuAvailability _availability;
  final List<RecipeCalibration> _history = <RecipeCalibration>[];

  /// The menu as measured.
  RecipeBook get book => _book;

  /// The store.
  InventoryLedger get ledger => _ledger;

  /// What the menu can sell, derived from both halves.
  MenuAvailability get availability => _availability;

  /// Who is making these changes.
  String get signedInAs => _signedInAs;

  /// Every calibration ever committed here, newest first.
  ///
  /// An audit trail rather than a undo stack: a published nutrition figure
  /// that changed twice in a service should show both changes and both
  /// authors, not collapse to the current value.
  List<RecipeCalibration> get history =>
      List<RecipeCalibration>.unmodifiable(_history);

  // -- Calibration --------------------------------------------------------

  /// A draft seeded with what [option] publishes, or with what it was last
  /// calibrated to.
  CalibrationDraft draftFor(IngredientOption option) =>
      CalibrationDraft.from(_book.resolve(option));

  /// Commits [draft] and rebuilds the menu around it.
  ///
  /// Returns the findings that were accepted. Throws through
  /// [CalibrationDraft.commit] if a blocking finding stands, which a caller
  /// avoids by gating on [CalibrationDraft.canCommit].
  List<CalibrationFinding> calibrate(
    CalibrationDraft draft, {
    required IngredientOption published,
  }) {
    final RecipeCalibration calibration = draft.commit(
      published: published,
      by: _signedInAs,
      at: _now(),
    );
    _book = _book.withCalibration(calibration);
    _history.insert(0, calibration);
    _recompute();
    return calibration.advisories;
  }

  /// Puts [componentId] back to what the menu publishes.
  void revertCalibration(String componentId) {
    final RecipeBook next = _book.withoutCalibration(componentId);
    if (identical(next, _book)) return;
    _book = next;
    _recompute();
  }

  // -- Inventory ----------------------------------------------------------

  /// Records a delivery.
  void receive(RawIngredient ingredient, Quantity amount) {
    _ledger.receive(ingredient, amount);
    _recompute();
  }

  /// Records a stock take.
  void setCount(RawIngredient ingredient, Quantity amount) {
    _ledger.setCount(ingredient, amount);
    _recompute();
  }

  /// Records waste or a staff meal.
  void writeOff(RawIngredient ingredient, Quantity amount) {
    _ledger.writeOff(ingredient, amount);
    _recompute();
  }

  /// Takes a component off the menu by hand, or puts it back.
  void setForcedOff(String componentId, {required bool off}) {
    _ledger.setForcedOff(componentId, off: off);
    _recompute();
  }

  /// Replaces the whole ledger — a fresh count, or a service starting.
  void replaceLedger(InventoryLedger ledger) {
    _ledger = ledger;
    _recompute();
  }

  // -- The order hook -----------------------------------------------------

  /// Deducts a placed order from the store.
  ///
  /// This is the one call the ordering side makes. Idempotent on [orderCode],
  /// so a retried placement does not cost the kitchen a second plate, and it
  /// never refuses: the food is being made either way, and a shortfall is
  /// reported rather than used to block a plate already on the pass.
  DeductionOutcome recordPlacedOrder(
    OrderDraft order, {
    required String orderCode,
  }) {
    final DeductionOutcome outcome = _ledger.deduct(
      orderCode: orderCode,
      components: order.components,
      scale: order.selection.scale,
      portions: _book,
    );
    if (outcome is DeductionApplied) _recompute();
    return outcome;
  }

  /// Puts back an order cancelled before it was made.
  DeductionOutcome recordCancelledOrder(
    OrderDraft order, {
    required String orderCode,
  }) {
    final DeductionOutcome outcome = _ledger.restore(
      orderCode: orderCode,
      components: order.components,
      scale: order.selection.scale,
      portions: _book,
    );
    if (outcome is DeductionApplied) _recompute();
    return outcome;
  }

  /// What one plate at [scale] would draw, without drawing it.
  ///
  /// The figure the calibrator shows beside a proposed change, so a manager
  /// can see what a heavier portion costs the store before saving it.
  Map<RawIngredient, Quantity> previewDraw({
    required List<IngredientOption> components,
    required PortionScale scale,
  }) {
    final InventoryLedger scratch = InventoryLedger(rails: _ledger.rails);
    final DeductionOutcome outcome = scratch.deduct(
      orderCode: 'preview',
      components: components,
      scale: scale,
      portions: _book,
    );
    return outcome.draw;
  }

  /// Re-derives availability and tells everyone once.
  ///
  /// A single notification per operation, whatever changed. A manager saving a
  /// calibration must not make the guest app rebuild three times, and
  /// availability must never be recomputed by a listener — if it were, two
  /// listeners could disagree about what is on the menu within one frame.
  void _recompute() {
    _availability = _ledger.availabilityWith(_book);
    notifyListeners();
  }
}
