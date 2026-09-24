import '../../../core/measure/quantity.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../../../core/menu/plate_segment.dart';
import '../../../core/nutrition/portion_scale.dart';
import 'plate_recipe.dart';
import 'raw_ingredient.dart';
import '../../../core/menu/recipe_book.dart';
import '../../../core/menu/stock_status.dart';

/// The rails the ledger runs on.
///
/// Named and injectable rather than hard-coded, because the right buffer is a
/// property of the site: a branch with a twice-daily delivery can run closer
/// to the bone than one resupplied on Tuesdays.
final class StockRails {
  /// Creates a set of rails.
  const StockRails({this.safetyBuffer = 5, this.lowWaterMark = 12})
      : assert(safetyBuffer >= 0, 'a buffer cannot be negative'),
        assert(
          lowWaterMark >= safetyBuffer,
          'the low-water mark sits above the buffer, or it never fires',
        );

  /// The house rails: stop selling at five portions, warn the manager at
  /// twelve.
  static const StockRails house = StockRails();

  /// The number of portions held back from sale.
  ///
  /// Selling stops *at* this count rather than at zero, and the difference is
  /// the whole point. A kitchen that sells its last portion has no margin for
  /// a miscount, a dropped tray or an order already on the line, and the way
  /// that failure surfaces is a guest being told no after they have paid.
  final int safetyBuffer;

  /// Where a manager starts being told to prep or order more.
  final int lowWaterMark;
}

/// What happened when an order was deducted.
///
/// Sealed, because "the deduction failed" is three different events and a
/// caller that treats them alike will either double-deduct a retry or silently
/// swallow an over-draw.
sealed class DeductionOutcome {
  const DeductionOutcome();

  /// The draw this order made, or would have made.
  Map<RawIngredient, Quantity> get draw;
}

/// The store was decremented.
final class DeductionApplied extends DeductionOutcome {
  /// Creates the applied outcome.
  const DeductionApplied({required this.draw, this.shortfalls = const {}});

  @override
  final Map<RawIngredient, Quantity> draw;

  /// Ingredients the book says there was not enough of.
  ///
  /// The deduction still applied: the food was cooked, whatever the book
  /// thought. A shortfall is a discrepancy to reconcile at the next count, not
  /// a reason to refuse an order that is already being plated.
  final Map<RawIngredient, Quantity> shortfalls;

  /// Whether the book and the shelf disagreed.
  bool get hasShortfall => shortfalls.isNotEmpty;

  @override
  String toString() =>
      'DeductionApplied(${draw.length} lines, ${shortfalls.length} short)';
}

/// This order was already deducted, and was not deducted again.
///
/// The property that makes the engine safe to call from a retry, a webhook
/// redelivery, or a kitchen board reconnecting after a dropped connection.
final class DeductionAlreadyApplied extends DeductionOutcome {
  /// Creates the duplicate outcome.
  const DeductionAlreadyApplied({required this.orderCode});

  /// The order that had already been counted.
  final String orderCode;

  @override
  Map<RawIngredient, Quantity> get draw => const {};

  @override
  String toString() => 'DeductionAlreadyApplied($orderCode)';
}

/// Nothing on the order had a recipe, so nothing could be deducted.
final class DeductionUnmapped extends DeductionOutcome {
  /// Creates the unmapped outcome.
  const DeductionUnmapped({required this.componentIds});

  /// The components with no recipe.
  final List<String> componentIds;

  @override
  Map<RawIngredient, Quantity> get draw => const {};

  @override
  String toString() => 'DeductionUnmapped($componentIds)';
}

/// The store, and what it can still make.
///
/// ## What this is, and what it deliberately is not
///
/// It is the book: what the last count said, less what has been sold since. It
/// is not the shelf. The two drift — a dropped tray, a staff meal, a generous
/// hand on the oil — and pretending otherwise is how a stock system loses the
/// kitchen's trust. Where the book and the shelf disagree, this says so
/// ([DeductionApplied.shortfalls]) rather than clamping quietly and moving on.
///
/// Counts are held as integer [Quantity] minor units, so several hundred
/// deductions a service leave a total that still reconciles exactly against
/// the count that started it.
final class InventoryLedger {
  /// Creates a ledger.
  InventoryLedger({
    this.rails = StockRails.house,
    Map<RawIngredient, Quantity> opening = const {},
  }) {
    opening.forEach(setCount);
  }

  /// A ledger stocked for [portions] plates, whatever those plates turn out
  /// to be. For tests and for a demo service.
  ///
  /// Not [portions] times the largest single recipe line, which is the obvious
  /// reading and the wrong one: a plate draws olive oil three times — once for
  /// the protein, once for the carb, once for the greens — so a store built to
  /// the largest single line runs out of oil in a third of the orders it
  /// claims to cover. The amount here is the worst case a plate can ask for,
  /// which is the largest line in each compartment, summed.
  factory InventoryLedger.stockedFor(
    int portions, {
    StockRails rails = StockRails.house,
  }) {
    final Map<RawIngredient, Map<PlateSegment, Quantity>> worstPerSegment =
        <RawIngredient, Map<PlateSegment, Quantity>>{};

    for (final PlateRecipe recipe in MawzoonRecipes.all) {
      final IngredientOption? option = MawzoonCatalog.optionById(
        recipe.componentId,
      );
      if (option == null) continue;
      for (final RecipeLine line in recipe.lines) {
        final Map<PlateSegment, Quantity> bySegment = worstPerSegment
            .putIfAbsent(line.ingredient, () => <PlateSegment, Quantity>{});
        final Quantity? held = bySegment[option.segment];
        if (held == null || line.amount.isAtLeast(held)) {
          bySegment[option.segment] = line.amount;
        }
      }
    }

    final Map<RawIngredient, Quantity> opening = <RawIngredient, Quantity>{};
    worstPerSegment.forEach((
      RawIngredient ingredient,
      Map<PlateSegment, Quantity> bySegment,
    ) {
      Quantity worstPlate = ingredient.none;
      for (final Quantity amount in bySegment.values) {
        worstPlate = worstPlate + amount;
      }
      opening[ingredient] = worstPlate * portions;
    });

    return InventoryLedger(rails: rails, opening: opening);
  }

  /// The rails this site runs on.
  final StockRails rails;

  final Map<RawIngredient, Quantity> _onHand = <RawIngredient, Quantity>{};
  final Set<String> _counted = <String>{};
  final Set<String> _forcedOff = <String>{};

  /// What the book says is on hand for [ingredient].
  Quantity onHand(RawIngredient ingredient) =>
      _onHand[ingredient] ?? ingredient.none;

  /// Every ingredient the ledger is tracking.
  Map<RawIngredient, Quantity> get counts =>
      Map<RawIngredient, Quantity>.unmodifiable(_onHand);

  /// Order codes already deducted.
  Set<String> get countedOrders => Set<String>.unmodifiable(_counted);

  /// Components a manager has taken off by hand.
  Set<String> get forcedOff => Set<String>.unmodifiable(_forcedOff);

  /// Records a stock take: this is what is actually on the shelf.
  ///
  /// Replaces the book value rather than adjusting it, because that is what a
  /// count is. A count is the only thing that can move the book *up* without a
  /// delivery.
  void setCount(RawIngredient ingredient, Quantity amount) {
    _requireUnit(ingredient, amount);
    _onHand[ingredient] = amount;
  }

  /// Records a delivery.
  void receive(RawIngredient ingredient, Quantity amount) {
    _requireUnit(ingredient, amount);
    _onHand[ingredient] = onHand(ingredient) + amount;
  }

  /// Records waste, a staff meal, or anything else that left without a sale.
  void writeOff(RawIngredient ingredient, Quantity amount) {
    _requireUnit(ingredient, amount);
    _onHand[ingredient] = onHand(ingredient) - amount;
  }

  /// Deducts the raw draw of one placed order.
  ///
  /// Idempotent on [orderCode]: calling it twice for the same order deducts
  /// once and says so. An order placement can be retried, replayed from a
  /// queue, or redelivered by a flaky webhook, and none of those should cost
  /// the kitchen a second chicken breast.
  DeductionOutcome deduct({
    required String orderCode,
    required List<IngredientOption> components,
    required PortionScale scale,
    PortionFactors portions = const UncalibratedPortions(),
  }) {
    if (_counted.contains(orderCode)) {
      return DeductionAlreadyApplied(orderCode: orderCode);
    }

    final Map<RawIngredient, Quantity> draw = <RawIngredient, Quantity>{};
    final List<String> unmapped = <String>[];

    for (final IngredientOption component in components) {
      final PlateRecipe? recipe = MawzoonRecipes.forOption(component);
      if (recipe == null) {
        unmapped.add(component.id);
        continue;
      }
      recipe
          .drawAt(
        scale,
        segment: component.segment,
        portionFactor: portions.portionFactorFor(component.id),
      )
          .forEach((RawIngredient ingredient, Quantity amount) {
        final Quantity? running = draw[ingredient];
        draw[ingredient] = running == null ? amount : running + amount;
      });
    }

    if (draw.isEmpty) return DeductionUnmapped(componentIds: unmapped);

    // Shortfalls are measured before anything is written, so the figure is
    // what the book was missing rather than what it was missing after a
    // partial application.
    final Map<RawIngredient, Quantity> shortfalls = <RawIngredient, Quantity>{};
    draw.forEach((RawIngredient ingredient, Quantity amount) {
      final Quantity held = onHand(ingredient);
      if (!held.isAtLeast(amount)) shortfalls[ingredient] = amount - held;
    });

    draw.forEach((RawIngredient ingredient, Quantity amount) {
      _onHand[ingredient] = onHand(ingredient) - amount;
    });
    _counted.add(orderCode);

    return DeductionApplied(draw: draw, shortfalls: shortfalls);
  }

  /// Puts back the draw of an order that was cancelled before it was made.
  ///
  /// Only an order the ledger actually counted, and only once — otherwise a
  /// double cancellation invents stock that was never there.
  DeductionOutcome restore({
    required String orderCode,
    required List<IngredientOption> components,
    required PortionScale scale,
    PortionFactors portions = const UncalibratedPortions(),
  }) {
    if (!_counted.remove(orderCode)) {
      return DeductionUnmapped(
        componentIds: components.map((IngredientOption o) => o.id).toList(),
      );
    }
    final Map<RawIngredient, Quantity> draw = <RawIngredient, Quantity>{};
    for (final IngredientOption component in components) {
      MawzoonRecipes.forOption(component)
          ?.drawAt(
        scale,
        segment: component.segment,
        portionFactor: portions.portionFactorFor(component.id),
      )
          .forEach((RawIngredient ingredient, Quantity amount) {
        final Quantity? running = draw[ingredient];
        draw[ingredient] = running == null ? amount : running + amount;
        _onHand[ingredient] = onHand(ingredient) + amount;
      });
    }
    return DeductionApplied(draw: draw);
  }

  /// Takes a component off the menu by hand, or puts it back.
  ///
  /// A manager's call outranks the count in both directions — they can stop
  /// selling something the book says is fine, but they cannot sell something
  /// the book says is below the buffer. Overriding a count with an opinion is
  /// how a guest ends up waiting for a dish nobody can make.
  void setForcedOff(String componentId, {required bool off}) {
    if (off) {
      _forcedOff.add(componentId);
    } else {
      _forcedOff.remove(componentId);
    }
  }

  /// How many standard portions of [componentId] the store can still make.
  ///
  /// The binding constraint, not the average: a recipe is only as makeable as
  /// its scarcest line. Five kilos of potato and no oil is no chips.
  int portionsFor(
    String componentId, {
    PortionFactors portions = const UncalibratedPortions(),
  }) {
    final PlateRecipe? recipe = MawzoonRecipes.forComponent(componentId);
    if (recipe == null) return _unlimited;

    final double factor = portions.portionFactorFor(componentId);
    int fewest = _unlimited;
    for (final RecipeLine line in recipe.lines) {
      final int fits = onHand(
        line.ingredient,
      ).howManyFit(line.amount * factor);
      if (fits < fewest) fewest = fits;
    }
    return fewest;
  }

  /// The line that is stopping [componentId], or `null` when nothing is.
  ///
  /// What a manager actually needs off a sold-out badge: not that the salad is
  /// off, but that it is off because of the parsley.
  RawIngredient? bindingConstraintFor(
    String componentId, {
    PortionFactors portions = const UncalibratedPortions(),
  }) {
    final PlateRecipe? recipe = MawzoonRecipes.forComponent(componentId);
    if (recipe == null) return null;

    final double factor = portions.portionFactorFor(componentId);
    RawIngredient? scarcest;
    int fewest = _unlimited;
    for (final RecipeLine line in recipe.lines) {
      final int fits = onHand(
        line.ingredient,
      ).howManyFit(line.amount * factor);
      if (fits < fewest) {
        fewest = fits;
        scarcest = line.ingredient;
      }
    }
    return scarcest;
  }

  /// The status of [componentId] against the rails.
  StockStatus statusFor(
    String componentId, {
    PortionFactors portions = const UncalibratedPortions(),
  }) =>
      StockStatus.from(
        portionsRemaining: portionsFor(componentId, portions: portions),
        safetyBuffer: rails.safetyBuffer,
        lowWaterMark: rails.lowWaterMark,
        forcedOff: _forcedOff.contains(componentId),
      );

  /// An immutable snapshot of what the menu can sell, measured through
  /// [portions] so a recalibrated portion changes what the store can make.
  MenuAvailability availabilityWith([
    PortionFactors portions = const UncalibratedPortions(),
  ]) =>
      MenuAvailability(<String, StockStatus>{
        for (final PlateRecipe recipe in MawzoonRecipes.all)
          recipe.componentId: statusFor(recipe.componentId, portions: portions),
      });

  /// An immutable snapshot against the menu exactly as published.
  MenuAvailability get availability => availabilityWith();

  void _requireUnit(RawIngredient ingredient, Quantity amount) {
    if (amount.unit != ingredient.unit) {
      throw ArgumentError(
        '${ingredient.id} is counted in ${ingredient.unit.name}, '
        'not ${amount.unit.name}',
      );
    }
  }

  /// A component with no recipe is not constrained by a store it does not
  /// draw on. Large rather than infinite so it stays an `int`.
  static const int _unlimited = 9999;
}
