import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/menu/recipe_book.dart';
import 'package:mawzoon/core/menu/recipe_calibration.dart';
import 'package:mawzoon/core/menu/stock_status.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/manager_suite/application/manager_suite_controller.dart';
import 'package:mawzoon/features/manager_suite/domain/inventory_ledger.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';
import 'package:mawzoon/features/plate_builder/application/plate_builder_controller.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';

void main() {
  const ProteinOption chicken = MawzoonCatalog.herbGrilledBreast;
  final DateTime when = DateTime.utc(2026, 5, 2, 15);

  CalibrationDraft leaner(IngredientOption of) => CalibrationDraft.from(of)
      .copyWith(proteinGrams: of.baseMacros.proteinGrams + 2, fatGrams: 1);

  /// A placeable pickup order built from three components.
  OrderDraft orderOf(List<IngredientOption> components) => OrderDraft(
        selection: PlateSelection(
          protein: components[0] as ProteinOption,
          carb: components[1] as CarbOption,
          fiber: components[2] as FiberOption,
        ),
        mode: FulfilmentMode.pickup,
        payment: PaymentMethod.cash,
      );

  // -------------------------------------------------------------------
  // The draft and its rails
  // -------------------------------------------------------------------

  group('draft', () {
    test('opens on what the component publishes', () {
      final CalibrationDraft draft = CalibrationDraft.from(chicken);
      expect(draft.componentId, chicken.id);
      expect(draft.portionGrams, chicken.basePortionGrams);
      expect(draft.proteinGrams, chicken.baseMacros.proteinGrams);
      expect(draft.fatGrams, chicken.baseMacros.fatGrams);
      expect(draft.differsFrom(chicken), isFalse);
      expect(draft.review(chicken), isEmpty);
    });

    test('every field can be read and written by name', () {
      CalibrationDraft draft = CalibrationDraft.from(chicken);
      for (final CalibrationField field in CalibrationField.values) {
        draft = draft.withField(field, 7);
        expect(draft.valueOf(field), 7);
      }
    });

    test('editing is immutable', () {
      final CalibrationDraft first = CalibrationDraft.from(chicken);
      first.withField(CalibrationField.protein, 99);
      expect(first.proteinGrams, chicken.baseMacros.proteinGrams);
    });

    test('a batch measurement is accepted without complaint', () {
      final CalibrationDraft draft = CalibrationDraft.from(
        chicken,
      ).copyWith(proteinGrams: chicken.baseMacros.proteinGrams + 1.5);
      expect(draft.differsFrom(chicken), isTrue);
      expect(draft.canCommit(chicken), isTrue);
      expect(draft.review(chicken), isEmpty);
    });
  });

  group('validation', () {
    test('fibre above carbohydrate is blocked, not asserted', () {
      // Without this rail the draft reaches MacroProfile's assert and takes
      // the app down in debug — a manager typing the fibre before fixing the
      // carbohydrate is an ordinary edit, not a programming error.
      final CalibrationDraft draft = CalibrationDraft.from(
        MawzoonCatalog.wholeBulgur,
      ).copyWith(carbohydrateGrams: 10, dietaryFiberGrams: 12);

      final List<CalibrationFinding> findings = draft.review(
        MawzoonCatalog.wholeBulgur,
      );
      expect(findings.first.isBlocking, isTrue);
      expect(findings.first.field, CalibrationField.fibre);
      expect(draft.canCommit(MawzoonCatalog.wholeBulgur), isFalse);
      expect(
        () => draft.commit(
          published: MawzoonCatalog.wholeBulgur,
          by: 'lina',
          at: when,
        ),
        throwsStateError,
      );
    });

    test('macros outweighing the portion is blocked, because physics', () {
      final CalibrationDraft draft = CalibrationDraft.from(
        chicken,
      ).copyWith(portionGrams: 150, proteinGrams: 200);
      final List<CalibrationFinding> findings = draft.review(chicken);
      expect(findings.any((CalibrationFinding f) => f.isBlocking), isTrue);
      expect(draft.canCommit(chicken), isFalse);
    });

    test('a negative number is blocked before anything else is checked', () {
      final CalibrationDraft draft = CalibrationDraft.from(
        chicken,
      ).copyWith(fatGrams: -1);
      final List<CalibrationFinding> findings = draft.review(chicken);
      expect(findings, hasLength(1));
      expect(findings.single.field, CalibrationField.fat);
      expect(findings.single.isBlocking, isTrue);
    });

    test('a portion of nothing is blocked', () {
      final CalibrationDraft draft = CalibrationDraft.from(
        chicken,
      ).copyWith(portionGrams: 0);
      expect(draft.canCommit(chicken), isFalse);
    });

    test('a large move is advised, and still allowed', () {
      // The kitchen is allowed to have measured something surprising. It is
      // not allowed to do so without being asked whether it meant to.
      final CalibrationDraft draft = CalibrationDraft.from(
        chicken,
      ).copyWith(fatGrams: chicken.baseMacros.fatGrams * 2);

      final List<CalibrationFinding> findings = draft.review(chicken);
      expect(findings, isNotEmpty);
      expect(findings.every((CalibrationFinding f) => !f.isBlocking), isTrue);
      expect(
        findings.any((CalibrationFinding f) => f.field == CalibrationField.fat),
        isTrue,
      );
      expect(draft.canCommit(chicken), isTrue);
    });

    test('a portion with no water left in it is advised', () {
      final CalibrationDraft draft = CalibrationDraft.from(chicken).copyWith(
        portionGrams: 100,
        proteinGrams: 50,
        carbohydrateGrams: 25,
        fatGrams: 20,
      );
      final List<CalibrationFinding> findings = draft.review(chicken);
      expect(findings.every((CalibrationFinding f) => !f.isBlocking), isTrue);
      expect(
        findings.any(
          (CalibrationFinding f) => f.field == CalibrationField.portionGrams,
        ),
        isTrue,
      );
    });

    test('blocking findings come before advisory ones', () {
      final CalibrationDraft draft = CalibrationDraft.from(chicken).copyWith(
        carbohydrateGrams: 1,
        dietaryFiberGrams: 9,
        fatGrams: chicken.baseMacros.fatGrams * 3,
      );
      expect(draft.review(chicken).first.isBlocking, isTrue);
    });

    test('every finding reads in both languages', () {
      final CalibrationDraft draft = CalibrationDraft.from(
        chicken,
      ).copyWith(carbohydrateGrams: 1, dietaryFiberGrams: 9);
      for (final CalibrationFinding finding in draft.review(chicken)) {
        expect(finding.message.ar, isNotEmpty);
        expect(finding.message.en, isNotEmpty);
        expect(finding.field.label.ar, isNotEmpty);
      }
    });
  });

  group('the committed record', () {
    test('carries who, when and why', () {
      final RecipeCalibration calibration = leaner(
        chicken,
      ).copyWith(note: 'batch 214 ran lean').commit(
            published: chicken,
            by: 'lina',
            at: when,
          );
      expect(calibration.by, 'lina');
      expect(calibration.at, when);
      expect(calibration.note, 'batch 214 ran lean');
      expect(calibration.componentId, chicken.id);
    });

    test('keeps the advisories that were accepted with it', () {
      final RecipeCalibration calibration = CalibrationDraft.from(chicken)
          .copyWith(fatGrams: chicken.baseMacros.fatGrams * 2)
          .commit(published: chicken, by: 'lina', at: when);
      expect(calibration.advisories, isNotEmpty);
      expect(
        calibration.advisories.every((CalibrationFinding f) => !f.isBlocking),
        isTrue,
      );
    });

    test('states how far the portion moved', () {
      final RecipeCalibration heavier = CalibrationDraft.from(chicken)
          .copyWith(portionGrams: chicken.basePortionGrams * 1.1)
          .commit(published: chicken, by: 'lina', at: when);
      expect(heavier.portionFactorAgainst(chicken), closeTo(1.1, 1e-9));
    });
  });

  // -------------------------------------------------------------------
  // The book
  // -------------------------------------------------------------------

  group('recipe book', () {
    RecipeBook bookWith(CalibrationDraft draft, IngredientOption published) =>
        RecipeBook.published.withCalibration(
          draft.commit(published: published, by: 'lina', at: when),
        );

    test('the published book changes nothing at all', () {
      expect(RecipeBook.published.isPublished, isTrue);
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(identical(RecipeBook.published.resolve(option), option), isTrue);
      }
    });

    test('a calibrated component reports the measured figures', () {
      final RecipeBook book = bookWith(leaner(chicken), chicken);
      final IngredientOption resolved = book.resolve(chicken);

      expect(resolved.id, chicken.id);
      expect(
        resolved.baseMacros.proteinGrams,
        chicken.baseMacros.proteinGrams + 2,
      );
      expect(resolved.baseMacros.fatGrams, 1);
      expect(resolved.baseKilocalories, isNot(chicken.baseKilocalories));
    });

    test('a calibrated protein is still a protein, with its doneness', () {
      final RecipeBook book = bookWith(leaner(chicken), chicken);
      final IngredientOption resolved = book.resolve(chicken);
      expect(resolved, isA<ProteinOption>());
      expect((resolved as ProteinOption).doneness, chicken.doneness);
      expect(resolved.segment, PlateSegment.protein);
      expect(resolved.kitchenNote, chicken.kitchenNote);
      expect(resolved.surchargeMinorUnits, chicken.surchargeMinorUnits);
      expect(resolved.allergens, chicken.allergens);
    });

    test('every kind of component survives the round trip', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final RecipeBook book = bookWith(
          CalibrationDraft.from(option).copyWith(
            portionGrams: option.basePortionGrams + 5,
          ),
          option,
        );
        final IngredientOption resolved = book.resolve(option);
        expect(resolved.runtimeType, option.runtimeType, reason: option.id);
        expect(resolved.segment, option.segment);
        expect(resolved.basePortionGrams, option.basePortionGrams + 5);
      }
    });

    test('an uncalibrated component is untouched, and identically so', () {
      final RecipeBook book = bookWith(leaner(chicken), chicken);
      expect(
        identical(
          book.resolve(MawzoonCatalog.steamedBasmati),
          MawzoonCatalog.steamedBasmati,
        ),
        isTrue,
      );
    });

    test('the carousel and the whole menu read through the book', () {
      final RecipeBook book = bookWith(leaner(chicken), chicken);
      final IngredientOption fromCarousel = book
          .optionsFor(PlateSegment.protein)
          .firstWhere((IngredientOption o) => o.id == chicken.id);
      expect(
        fromCarousel.baseMacros.proteinGrams,
        chicken.baseMacros.proteinGrams + 2,
      );
      expect(book.all, hasLength(MawzoonCatalog.all.length));
      expect(book.optionById(chicken.id)!.baseMacros.fatGrams, 1);
      expect(book.optionById('nope'), isNull);
    });

    test('reverting puts the published figures back', () {
      final RecipeBook book = bookWith(leaner(chicken), chicken);
      final RecipeBook reverted = book.withoutCalibration(chicken.id);
      expect(reverted.isPublished, isTrue);
      expect(identical(reverted.resolve(chicken), chicken), isTrue);
      expect(
        identical(reverted.withoutCalibration('nothing.here'), reverted),
        isTrue,
      );
    });

    test('the portion factor is one until a portion actually moves', () {
      final RecipeBook book = bookWith(leaner(chicken), chicken);
      expect(book.portionFactorFor(chicken.id), 1);
      expect(book.portionFactorFor('nothing.here'), 1);

      final RecipeBook heavier = bookWith(
        CalibrationDraft.from(
          chicken,
        ).copyWith(portionGrams: chicken.basePortionGrams * 1.2),
        chicken,
      );
      expect(heavier.portionFactorFor(chicken.id), closeTo(1.2, 1e-9));
    });
  });

  // -------------------------------------------------------------------
  // The suite, end to end
  // -------------------------------------------------------------------

  group('manager suite', () {
    ManagerSuiteController suite({int portions = 60}) => ManagerSuiteController(
          ledger: InventoryLedger.stockedFor(portions),
          now: () => when,
          signedInAs: 'lina',
        );

    final OrderDraft order = orderOf(const <IngredientOption>[
      chicken,
      MawzoonCatalog.airFriedSpicedPotatoes,
      MawzoonCatalog.charredGardenVeggies,
    ]);

    test('a calibration reaches the menu and stamps the author', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      manager.calibrate(leaner(chicken), published: chicken);

      expect(
        manager.book.resolve(chicken).baseMacros.fatGrams,
        1,
      );
      expect(manager.history, hasLength(1));
      expect(manager.history.single.by, 'lina');
      expect(manager.history.single.at, when);
    });

    test('it notifies once per change, not once per derived thing', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      int notifications = 0;
      manager.addListener(() => notifications++);

      manager.calibrate(leaner(chicken), published: chicken);
      expect(notifications, 1);

      manager.recordPlacedOrder(order, orderCode: 'M-1');
      expect(notifications, 2);
    });

    test('a placed order depletes the store through the suite', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      final Quantity before = manager.ledger.onHand(RawStore.potato);
      final DeductionOutcome outcome = manager.recordPlacedOrder(
        order,
        orderCode: 'M-1',
      );

      expect(outcome, isA<DeductionApplied>());
      expect(
        manager.ledger.onHand(RawStore.potato),
        before - Quantity.grams(220),
      );
    });

    test('a retried placement is counted once and reports why', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      manager.recordPlacedOrder(order, orderCode: 'M-1');
      final Quantity after = manager.ledger.onHand(RawStore.potato);

      expect(
        manager.recordPlacedOrder(order, orderCode: 'M-1'),
        isA<DeductionAlreadyApplied>(),
      );
      expect(manager.ledger.onHand(RawStore.potato), after);
    });

    test('a heavier portion draws more from the store on the next order', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      manager.calibrate(
        CalibrationDraft.from(MawzoonCatalog.airFriedSpicedPotatoes).copyWith(
          portionGrams:
              MawzoonCatalog.airFriedSpicedPotatoes.basePortionGrams * 1.5,
        ),
        published: MawzoonCatalog.airFriedSpicedPotatoes,
      );

      final Quantity before = manager.ledger.onHand(RawStore.potato);
      manager.recordPlacedOrder(order, orderCode: 'M-1');

      // 220g at the published portion; 330g at one measured half again as
      // heavy. An inventory that did not follow the recipe would be wrong
      // from the moment the recipe changed.
      expect(
        before - manager.ledger.onHand(RawStore.potato),
        Quantity.grams(330),
      );
    });

    test('a heavier portion also cuts how many portions are left', () {
      final ManagerSuiteController manager = suite(portions: 30);
      addTearDown(manager.dispose);

      final String chips = MawzoonCatalog.airFriedSpicedPotatoes.id;
      final int before = manager.availability.statusOf(chips).portionsRemaining;

      manager.calibrate(
        CalibrationDraft.from(MawzoonCatalog.airFriedSpicedPotatoes).copyWith(
          portionGrams:
              MawzoonCatalog.airFriedSpicedPotatoes.basePortionGrams * 2,
        ),
        published: MawzoonCatalog.airFriedSpicedPotatoes,
      );

      expect(
        manager.availability.statusOf(chips).portionsRemaining,
        closeTo(before / 2, 1),
      );
    });

    test('selling past the rail takes the dish off the menu', () {
      final ManagerSuiteController manager = suite(portions: 7);
      addTearDown(manager.dispose);

      final String chips = MawzoonCatalog.airFriedSpicedPotatoes.id;
      expect(manager.availability.canOrder(chips), isTrue);

      for (int i = 0; i < 3; i++) {
        manager.recordPlacedOrder(order, orderCode: 'M-$i');
      }

      expect(manager.availability.canOrder(chips), isFalse);
      expect(
        (manager.availability.statusOf(chips) as SoldOut).reason,
        SoldOutReason.belowSafetyBuffer,
      );
    });

    test('a cancellation puts it back on the menu', () {
      final ManagerSuiteController manager = suite(portions: 7);
      addTearDown(manager.dispose);
      final String chips = MawzoonCatalog.airFriedSpicedPotatoes.id;

      for (int i = 0; i < 3; i++) {
        manager.recordPlacedOrder(order, orderCode: 'M-$i');
      }
      expect(manager.availability.canOrder(chips), isFalse);

      manager.recordCancelledOrder(order, orderCode: 'M-2');
      expect(manager.availability.canOrder(chips), isTrue);
    });

    test('a draw can be previewed without drawing it', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      final Quantity before = manager.ledger.onHand(RawStore.potato);
      final Map<RawIngredient, Quantity> preview = manager.previewDraw(
        components: order.components,
        scale: PortionScale.standardBalance,
      );

      expect(preview[RawStore.potato], Quantity.grams(220));
      expect(manager.ledger.onHand(RawStore.potato), before);
    });

    test('reverting a calibration reaches the menu too', () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      manager.calibrate(leaner(chicken), published: chicken);
      manager.revertCalibration(chicken.id);

      expect(manager.book.isPublished, isTrue);
      expect(
        manager.book.resolve(chicken).baseMacros.fatGrams,
        chicken.baseMacros.fatGrams,
      );
      // The history is an audit trail, not an undo stack: the change happened
      // and reverting it does not unhappen it.
      expect(manager.history, hasLength(1));
    });

    test('a draft is seeded from the measured figures, not the published ones',
        () {
      final ManagerSuiteController manager = suite();
      addTearDown(manager.dispose);

      manager.calibrate(leaner(chicken), published: chicken);
      expect(manager.draftFor(chicken).fatGrams, 1);
    });
  });

  // -------------------------------------------------------------------
  // A live session must survive all of this
  // -------------------------------------------------------------------

  group('a plate already on screen', () {
    test('keeps its components and picks up the new figures', () {
      final PlateBuilderController plate = PlateBuilderController(
        initialSelection: const PlateSelection(
          protein: chicken,
          carb: MawzoonCatalog.steamedBasmati,
        ),
      );
      addTearDown(plate.dispose);

      final double before = plate.macros.totalKilocalories;
      final RecipeBook book = RecipeBook.published.withCalibration(
        CalibrationDraft.from(chicken)
            .copyWith(fatGrams: chicken.baseMacros.fatGrams + 6)
            .commit(published: chicken, by: 'lina', at: when),
      );

      plate.rebase(book);

      expect(plate.selection.protein!.id, chicken.id);
      expect(plate.selection.carb!.id, MawzoonCatalog.steamedBasmati.id);
      expect(plate.selection.fiber, isNull, reason: 'still half-built');
      expect(plate.selection.scale, PortionScale.standardBalance);
      expect(plate.macros.totalKilocalories, greaterThan(before));
      expect(plate.macros.totalKilocalories, closeTo(before + 6 * 9, 0.001));
    });

    test('the rebase actually reaches a listener', () {
      // The trap this guards: PlateBuilderState compared components by id, so
      // a recalibration produced a state `==` the old one and ValueNotifier
      // silently dropped it — leaving the canvas painting superseded figures.
      final PlateBuilderController plate = PlateBuilderController(
        initialSelection: const PlateSelection(protein: chicken),
      );
      addTearDown(plate.dispose);

      int notifications = 0;
      plate.addListener(() => notifications++);

      plate.rebase(
        RecipeBook.published.withCalibration(
          CalibrationDraft.from(chicken)
              .copyWith(fatGrams: chicken.baseMacros.fatGrams + 6)
              .commit(published: chicken, by: 'lina', at: when),
        ),
      );

      expect(notifications, 1);
    });

    test('an unchanged menu does not disturb it', () {
      final PlateBuilderController plate = PlateBuilderController(
        initialSelection: const PlateSelection(protein: chicken),
      );
      addTearDown(plate.dispose);

      int notifications = 0;
      plate.addListener(() => notifications++);
      plate.rebase(RecipeBook.published);

      expect(notifications, 0);
    });

    test('the volume toggle and a complete plate both survive', () {
      final PlateBuilderController plate = PlateBuilderController(
        initialSelection: const PlateSelection(
          protein: chicken,
          carb: MawzoonCatalog.steamedBasmati,
          fiber: MawzoonCatalog.charredGardenVeggies,
          scale: PortionScale.athleticLoad,
        ),
      );
      addTearDown(plate.dispose);

      plate.rebase(
        RecipeBook.published.withCalibration(
          CalibrationDraft.from(chicken)
              .copyWith(proteinGrams: chicken.baseMacros.proteinGrams + 3)
              .commit(published: chicken, by: 'lina', at: when),
        ),
      );

      expect(plate.selection.isComplete, isTrue);
      expect(plate.selection.scale, PortionScale.athleticLoad);
      expect(plate.canCheckout, isTrue);
    });

    test('a component going out does not empty the compartment', () {
      // The rail must never reach into a plate. A guest who assembled
      // something while the last tray was sold has not made a mistake.
      final ManagerSuiteController manager = ManagerSuiteController(
        ledger: InventoryLedger.stockedFor(7),
        now: () => when,
      );
      addTearDown(manager.dispose);

      final PlateBuilderController plate = PlateBuilderController(
        initialSelection: const PlateSelection(
          protein: chicken,
          carb: MawzoonCatalog.airFriedSpicedPotatoes,
          fiber: MawzoonCatalog.charredGardenVeggies,
        ),
      );
      addTearDown(plate.dispose);

      final OrderDraft other = orderOf(const <IngredientOption>[
        chicken,
        MawzoonCatalog.airFriedSpicedPotatoes,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      for (int i = 0; i < 3; i++) {
        manager.recordPlacedOrder(other, orderCode: 'M-$i');
      }

      expect(
        manager.availability.canOrder(
          MawzoonCatalog.airFriedSpicedPotatoes.id,
        ),
        isFalse,
      );
      expect(plate.selection.isComplete, isTrue);
      expect(
        plate.selection.carb!.id,
        MawzoonCatalog.airFriedSpicedPotatoes.id,
      );
    });

    test('checkout is where the guest is told, by name', () {
      final ManagerSuiteController manager = ManagerSuiteController(
        ledger: InventoryLedger.stockedFor(7),
        now: () => when,
      );
      addTearDown(manager.dispose);

      final OrderDraft draft = orderOf(const <IngredientOption>[
        chicken,
        MawzoonCatalog.airFriedSpicedPotatoes,
        MawzoonCatalog.charredGardenVeggies,
      ]);

      expect(draft.blockerIn(manager.availability), isNull);
      expect(draft.isPlaceableIn(manager.availability), isTrue);

      for (int i = 0; i < 3; i++) {
        manager.recordPlacedOrder(draft, orderCode: 'M-$i');
      }

      expect(draft.isPlaceableIn(manager.availability), isFalse);

      final List<IngredientOption> gone = draft.unavailableIn(
        manager.availability,
      );
      expect(gone, isNotEmpty);
      // Whichever went out, the guest is told which one by name rather than
      // handed a generic refusal to go and diagnose.
      expect(
        draft.blockerIn(manager.availability)!.en,
        contains(gone.first.name.en),
      );
      expect(
        draft.blockerIn(manager.availability)!.ar,
        contains(gone.first.name.ar),
      );
    });

    test('an unfinished plate is told to finish before it is told no', () {
      const OrderDraft half = OrderDraft(
        selection: PlateSelection(protein: chicken),
        mode: FulfilmentMode.pickup,
        payment: PaymentMethod.cash,
      );
      expect(
        half.blockerIn(InventoryLedger().availability)!.en,
        'Finish all three compartments',
      );
    });
  });
}
