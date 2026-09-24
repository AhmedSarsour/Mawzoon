import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/stock_status.dart';
import 'package:mawzoon/core/nutrition/macro_profile.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/manager_suite/domain/inventory_ledger.dart';
import 'package:mawzoon/features/manager_suite/domain/plate_recipe.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';

void main() {
  const List<IngredientOption> plate = <IngredientOption>[
    MawzoonCatalog.airFriedSpicedPotatoes,
  ];

  // -------------------------------------------------------------------
  // The bill of materials
  // -------------------------------------------------------------------

  group('recipes', () {
    test('every menu component has one', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(
          MawzoonRecipes.forOption(option),
          isNotNull,
          reason: '${option.id} cannot be deducted from the store',
        );
      }
      expect(MawzoonRecipes.all, hasLength(MawzoonCatalog.all.length));
    });

    test('the brief\'s own example, to the gram and the millilitre', () {
      final PlateRecipe chips = MawzoonRecipes.forOption(
        MawzoonCatalog.airFriedSpicedPotatoes,
      )!;
      final Map<RawIngredient, Quantity> draw = chips.drawAt(
        PortionScale.standardBalance,
        segment: PlateSegment.smartCarb,
      );
      expect(draw[RawStore.potato], Quantity.grams(220));
      expect(draw[RawStore.oliveOil], Quantity.millilitres(5));
    });

    test('every line is stated in its own ingredient\'s unit', () {
      for (final PlateRecipe recipe in MawzoonRecipes.all) {
        for (final RecipeLine line in recipe.lines) {
          expect(line.amount.unit, line.ingredient.unit, reason: '$line');
          expect(line.amount.minorUnits, greaterThan(0));
        }
      }
    });

    test('a line cannot be stated in the wrong unit', () {
      expect(
        () => RecipeLine(
          ingredient: RawStore.oliveOil,
          amount: Quantity.grams(5),
        ),
        throwsAssertionError,
      );
      expect(
        () => RecipeLine(
          ingredient: RawStore.potato,
          amount: Quantity.grams(0),
        ),
        throwsAssertionError,
      );
    });

    test('grilled proteins lose mass and dry grains gain it', () {
      // The yield gap is the whole reason raw and cooked are separate numbers.
      for (final IngredientOption protein in MawzoonCatalog.proteins) {
        final double yield_ = MawzoonRecipes.forOption(
          protein,
        )!
            .yieldAgainst(protein)!;
        expect(
          yield_,
          inInclusiveRange(0.5, 0.85),
          reason: '${protein.id} yields ${yield_.toStringAsFixed(2)}',
        );
      }
      for (final IngredientOption grain in <IngredientOption>[
        MawzoonCatalog.steamedBasmati,
        MawzoonCatalog.wholeBulgur,
        MawzoonCatalog.toastedQuinoa,
        MawzoonCatalog.wholeWheatPasta,
      ]) {
        expect(
          MawzoonRecipes.forOption(grain)!.yieldAgainst(grain),
          greaterThan(2),
          reason: '${grain.id} should swell, not shrink',
        );
      }
    });

    test('an Athletic Load draws more raw, by the plate\'s own factor', () {
      final PlateRecipe chips = MawzoonRecipes.forOption(
        MawzoonCatalog.airFriedSpicedPotatoes,
      )!;
      final Quantity standard = chips.drawAt(
        PortionScale.standardBalance,
        segment: PlateSegment.smartCarb,
      )[RawStore.potato]!;
      final Quantity athletic = chips.drawAt(
        PortionScale.athleticLoad,
        segment: PlateSegment.smartCarb,
      )[RawStore.potato]!;
      expect(
        athletic,
        standard * PortionScale.athleticLoad.factorFor(PlateSegment.smartCarb),
      );
      expect(athletic, Quantity.grams(330));
    });

    test('a repeated ingredient is summed, not overwritten', () {
      final PlateRecipe salad = MawzoonRecipes.forOption(
        MawzoonCatalog.mediterraneanSumacSalad,
      )!;
      final Map<RawIngredient, Quantity> draw = salad.drawAt(
        PortionScale.standardBalance,
        segment: PlateSegment.vitalFiber,
      );
      expect(draw.keys, hasLength(salad.lines.length));
      expect(draw[RawStore.lemon], Quantity.pieces(0.2));
    });

    test('a recalibrated portion moves the raw draw with it', () {
      final PlateRecipe chips = MawzoonRecipes.forOption(
        MawzoonCatalog.airFriedSpicedPotatoes,
      )!;
      final Quantity heavier = chips.drawAt(
        PortionScale.standardBalance,
        segment: PlateSegment.smartCarb,
        portionFactor: 1.1,
      )[RawStore.potato]!;
      expect(heavier, Quantity.grams(242));
    });

    test('the store knows which dishes each ingredient holds up', () {
      expect(
        MawzoonRecipes.componentsUsing(RawStore.potato),
        <String>[MawzoonCatalog.airFriedSpicedPotatoes.id],
      );
      expect(
        MawzoonRecipes.componentsUsing(RawStore.oliveOil).length,
        greaterThan(5),
      );
    });
  });

  // -------------------------------------------------------------------
  // Depletion
  // -------------------------------------------------------------------

  group('depletion', () {
    test('a placed order comes straight off the shelf', () {
      final InventoryLedger ledger = InventoryLedger(
        opening: <RawIngredient, Quantity>{
          RawStore.potato: Quantity.kilograms(10),
          RawStore.oliveOil: Quantity.litres(2),
          RawStore.houseSpiceBlend: Quantity.grams(500),
        },
      );

      final DeductionOutcome outcome = ledger.deduct(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );

      expect(outcome, isA<DeductionApplied>());
      expect((outcome as DeductionApplied).hasShortfall, isFalse);
      expect(ledger.onHand(RawStore.potato), Quantity.grams(10000 - 220));
      expect(ledger.onHand(RawStore.oliveOil), Quantity.millilitres(2000 - 5));
      expect(ledger.onHand(RawStore.houseSpiceBlend), Quantity.grams(497));
    });

    test('a whole plate draws on all three stations at once', () {
      final InventoryLedger ledger = InventoryLedger.stockedFor(20);
      ledger.deduct(
        orderCode: 'M-1',
        components: const <IngredientOption>[
          MawzoonCatalog.herbGrilledBreast,
          MawzoonCatalog.steamedBasmati,
          MawzoonCatalog.mediterraneanSumacSalad,
        ],
        scale: PortionScale.standardBalance,
      );
      expect(ledger.onHand(RawStore.chickenBreast).amount, lessThan(210 * 20));
      expect(ledger.onHand(RawStore.basmatiRice).amount, lessThan(55 * 20));
      expect(ledger.onHand(RawStore.cucumber).amount, lessThan(55 * 20));
    });

    test('deducting the same order twice deducts once', () {
      final InventoryLedger ledger = InventoryLedger(
        opening: <RawIngredient, Quantity>{
          RawStore.potato: Quantity.kilograms(10),
          RawStore.oliveOil: Quantity.litres(2),
          RawStore.houseSpiceBlend: Quantity.grams(500),
        },
      );

      ledger.deduct(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );
      final DeductionOutcome second = ledger.deduct(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );

      expect(second, isA<DeductionAlreadyApplied>());
      expect(ledger.onHand(RawStore.potato), Quantity.grams(10000 - 220));
      expect(ledger.countedOrders, <String>{'M-1'});
    });

    test('a different order with the same plate does deduct again', () {
      final InventoryLedger ledger = InventoryLedger(
        opening: <RawIngredient, Quantity>{
          RawStore.potato: Quantity.kilograms(10),
          RawStore.oliveOil: Quantity.litres(2),
          RawStore.houseSpiceBlend: Quantity.grams(500),
        },
      );
      for (final String code in <String>['M-1', 'M-2']) {
        ledger.deduct(
          orderCode: code,
          components: plate,
          scale: PortionScale.standardBalance,
        );
      }
      expect(ledger.onHand(RawStore.potato), Quantity.grams(10000 - 440));
    });

    test('an over-draw is reported, never used to refuse the plate', () {
      final InventoryLedger ledger = InventoryLedger(
        opening: <RawIngredient, Quantity>{
          RawStore.potato: Quantity.grams(100),
          RawStore.oliveOil: Quantity.litres(1),
          RawStore.houseSpiceBlend: Quantity.grams(500),
        },
      );

      final DeductionOutcome outcome = ledger.deduct(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );

      expect(outcome, isA<DeductionApplied>());
      final DeductionApplied applied = outcome as DeductionApplied;
      expect(applied.hasShortfall, isTrue);
      expect(applied.shortfalls[RawStore.potato], Quantity.grams(120));
      expect(applied.shortfalls.containsKey(RawStore.oliveOil), isFalse);
      // The food was cooked either way, so the book goes to zero rather than
      // negative and the discrepancy is the shortfall, not a signed count.
      expect(ledger.onHand(RawStore.potato).isZero, isTrue);
    });

    test('a component with no recipe is named rather than silently skipped',
        () {
      final InventoryLedger ledger = InventoryLedger();
      final DeductionOutcome outcome = ledger.deduct(
        orderCode: 'M-1',
        components: const <IngredientOption>[
          CarbOption(
            id: 'carb.not_on_the_menu',
            name: LocalizedTextStub.name,
            description: LocalizedTextStub.name,
            basePortionGrams: 100,
            baseMacros: MacroProfileStub.zero,
            method: CookingMethod.steamed,
            allergens: <Allergen>{},
            dietaryTags: <DietaryTag>{},
          ),
        ],
        scale: PortionScale.standardBalance,
      );
      expect(outcome, isA<DeductionUnmapped>());
      expect(
        (outcome as DeductionUnmapped).componentIds,
        <String>['carb.not_on_the_menu'],
      );
      expect(ledger.countedOrders, isEmpty);
    });

    test('a cancellation puts the draw back, once', () {
      final InventoryLedger ledger = InventoryLedger(
        opening: <RawIngredient, Quantity>{
          RawStore.potato: Quantity.kilograms(10),
          RawStore.oliveOil: Quantity.litres(2),
          RawStore.houseSpiceBlend: Quantity.grams(500),
        },
      );
      ledger.deduct(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );
      ledger.restore(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );
      expect(ledger.onHand(RawStore.potato), Quantity.kilograms(10));

      // A second cancellation must not invent stock that was never there.
      ledger.restore(
        orderCode: 'M-1',
        components: plate,
        scale: PortionScale.standardBalance,
      );
      expect(ledger.onHand(RawStore.potato), Quantity.kilograms(10));
    });

    test('a delivery adds and a stock take replaces', () {
      final InventoryLedger ledger = InventoryLedger();
      ledger.receive(RawStore.potato, Quantity.kilograms(5));
      ledger.receive(RawStore.potato, Quantity.kilograms(5));
      expect(ledger.onHand(RawStore.potato), Quantity.kilograms(10));

      ledger.setCount(RawStore.potato, Quantity.kilograms(8.4));
      expect(ledger.onHand(RawStore.potato), Quantity.kilograms(8.4));

      ledger.writeOff(RawStore.potato, Quantity.kilograms(1));
      expect(ledger.onHand(RawStore.potato), Quantity.kilograms(7.4));
    });

    test('a count in the wrong unit is refused', () {
      final InventoryLedger ledger = InventoryLedger();
      expect(
        () => ledger.setCount(RawStore.oliveOil, Quantity.grams(500)),
        throwsArgumentError,
      );
    });
  });

  // -------------------------------------------------------------------
  // The rails
  // -------------------------------------------------------------------

  group('safety rails', () {
    /// A ledger holding exactly [portions] of the chips and nothing scarcer.
    InventoryLedger chipsFor(int portions) => InventoryLedger(
          opening: <RawIngredient, Quantity>{
            RawStore.potato: Quantity.grams(220.0 * portions),
            RawStore.oliveOil: Quantity.millilitres(5.0 * portions),
            RawStore.houseSpiceBlend: Quantity.grams(3.0 * portions),
          },
        );

    final String chips = MawzoonCatalog.airFriedSpicedPotatoes.id;

    test('portions remaining is the scarcest line, not the average', () {
      final InventoryLedger ledger = InventoryLedger(
        opening: <RawIngredient, Quantity>{
          // Five kilos of potato and almost no oil is no chips.
          RawStore.potato: Quantity.kilograms(5),
          RawStore.oliveOil: Quantity.millilitres(30),
          RawStore.houseSpiceBlend: Quantity.grams(500),
        },
      );
      expect(ledger.portionsFor(chips), 6);
      expect(ledger.bindingConstraintFor(chips), RawStore.oliveOil);
    });

    test('the rail is five portions, and it is a floor not a ceiling', () {
      expect(chipsFor(6).statusFor(chips), isA<RunningLow>());
      expect(chipsFor(5).statusFor(chips), isA<RunningLow>());
      expect(chipsFor(4).statusFor(chips), isA<SoldOut>());
      expect(chipsFor(0).statusFor(chips), isA<SoldOut>());
    });

    test('selling stops with the buffer still on the shelf', () {
      final InventoryLedger ledger = chipsFor(4);
      final StockStatus status = ledger.statusFor(chips);
      expect(status, isA<SoldOut>());
      expect((status as SoldOut).reason, SoldOutReason.belowSafetyBuffer);
      // The point of the rail: four portions are still there, held back.
      expect(status.portionsRemaining, 4);
      expect(ledger.onHand(RawStore.potato).isZero, isFalse);
    });

    test('a manager is warned before a guest is told no', () {
      expect(chipsFor(40).statusFor(chips), isA<InStock>());
      expect(chipsFor(13).statusFor(chips), isA<InStock>());
      expect(chipsFor(12).statusFor(chips), isA<RunningLow>());
      expect(chipsFor(12).statusFor(chips).isOrderable, isTrue);
      expect(chipsFor(12).statusFor(chips).needsAttention, isTrue);
    });

    test('the rails are a property of the site, not of the code', () {
      final InventoryLedger lean = InventoryLedger(
        rails: const StockRails(safetyBuffer: 2, lowWaterMark: 4),
        opening: chipsFor(3).counts,
      );
      expect(lean.statusFor(chips), isA<RunningLow>());
      expect(lean.statusFor(chips).isOrderable, isTrue);
    });

    test('a low-water mark under the buffer would never fire', () {
      expect(
        () => StockRails(safetyBuffer: 10, lowWaterMark: 4),
        throwsAssertionError,
      );
    });

    test('a manager can stop selling something the count says is fine', () {
      final InventoryLedger ledger = chipsFor(80);
      expect(ledger.statusFor(chips), isA<InStock>());

      ledger.setForcedOff(chips, off: true);
      final StockStatus status = ledger.statusFor(chips);
      expect(status, isA<SoldOut>());
      expect((status as SoldOut).reason, SoldOutReason.takenOff);
      expect(status.portionsRemaining, 80, reason: 'the stock is still there');

      ledger.setForcedOff(chips, off: false);
      expect(ledger.statusFor(chips), isA<InStock>());
    });

    test('a manager cannot sell what the count says is not there', () {
      // The override runs one way. Overriding a count with an opinion is how
      // a guest ends up waiting for a dish nobody can make.
      final InventoryLedger ledger = chipsFor(1);
      ledger.setForcedOff(chips, off: false);
      expect(ledger.statusFor(chips), isA<SoldOut>());
    });

    test('selling crosses the rail exactly when the count says it does', () {
      final InventoryLedger ledger = chipsFor(7);
      expect(ledger.statusFor(chips).isOrderable, isTrue);

      for (int i = 0; i < 3; i++) {
        ledger.deduct(
          orderCode: 'M-$i',
          components: plate,
          scale: PortionScale.standardBalance,
        );
      }

      expect(ledger.portionsFor(chips), 4);
      expect(ledger.statusFor(chips), isA<SoldOut>());
      expect(ledger.availability.canOrder(chips), isFalse);
    });

    test('an availability snapshot covers the whole menu', () {
      final MenuAvailability availability = InventoryLedger.stockedFor(
        60,
      ).availability;
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(availability.canOrder(option.id), isTrue, reason: option.id);
      }
      expect(availability.soldOut, isEmpty);
    });

    test('an empty store sells nothing, and says so for every dish', () {
      final MenuAvailability availability = InventoryLedger().availability;
      expect(availability.soldOut, hasLength(MawzoonCatalog.all.length));
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(availability.statusOf(option.id).portionsRemaining, 0);
      }
    });

    test('a snapshot has value equality, so a scope can skip a rebuild', () {
      final InventoryLedger a = InventoryLedger.stockedFor(60);
      final InventoryLedger b = InventoryLedger.stockedFor(60);
      expect(a.availability, b.availability);
      expect(a.availability.hashCode, b.availability.hashCode);

      b.setForcedOff(MawzoonCatalog.steamedBasmati.id, off: true);
      expect(a.availability, isNot(b.availability));
    });

    test('a component the snapshot never heard of is orderable', () {
      // A new dish shipping ahead of its recipe must not hide itself.
      expect(MenuAvailability.everything.canOrder('carb.brand_new'), isTrue);
    });
  });
}

/// Stubs for the one test that needs a component the catalogue does not have.
abstract final class LocalizedTextStub {
  static const LocalizedText name =
      LocalizedText(ar: 'غير معروف', en: 'Unknown');
}

abstract final class MacroProfileStub {
  static const MacroProfile zero = MacroProfile(
    proteinGrams: 1,
    carbohydrateGrams: 1,
    fatGrams: 1,
    dietaryFiberGrams: 0,
  );
}
