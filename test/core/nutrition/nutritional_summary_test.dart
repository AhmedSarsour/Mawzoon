import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/balance_band.dart';
import 'package:mawzoon/core/nutrition/glycemic.dart';
import 'package:mawzoon/core/nutrition/nutritional_summary.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';

NutritionalSummary _summaryOf(
  List<IngredientOption> options, {
  PortionScale scale = PortionScale.standardBalance,
}) =>
    NutritionalSummary.fromComponents(
      scale: scale,
      components: options.map((IngredientOption o) => o.atScale(scale)),
    );

void main() {
  group('empty plate', () {
    test('reports three unfilled compartments and no energy', () {
      final NutritionalSummary summary =
          NutritionalSummary.empty(PortionScale.standardBalance);

      expect(summary.isEmpty, isTrue);
      expect(summary.isComplete, isFalse);
      expect(summary.totalKilocalories, 0);
      expect(summary.remainingSegmentCount, 3);
      expect(summary.contributions.length, 3);
      expect(summary.nextSegment, PlateSegment.protein);
    });

    test('divides by zero nowhere — every share is zero', () {
      final NutritionalSummary summary =
          NutritionalSummary.empty(PortionScale.athleticLoad);

      expect(summary.proteinEnergyShare, 0);
      expect(summary.carbohydrateEnergyShare, 0);
      expect(summary.fatEnergyShare, 0);
      expect(summary.nominalProgress, 0);
      for (final PlateSegment segment in PlateSegment.values) {
        expect(summary.contributionFor(segment).energyShare, 0);
        expect(summary.contributionFor(segment).isFilled, isFalse);
      }
    });
  });

  group('partial plate', () {
    test('tracks which compartment comes next', () {
      final NutritionalSummary summary =
          _summaryOf(<IngredientOption>[MawzoonCatalog.herbGrilledBreast]);

      expect(summary.isEmpty, isFalse);
      expect(summary.isComplete, isFalse);
      expect(summary.remainingSegmentCount, 2);
      expect(summary.nextSegment, PlateSegment.smartCarb);
      expect(summary.filledSegments, <PlateSegment>{PlateSegment.protein});
    });

    test('a single component owns the entire energy share', () {
      final NutritionalSummary summary =
          _summaryOf(<IngredientOption>[MawzoonCatalog.steamedBasmati]);

      expect(
        summary.contributionFor(PlateSegment.smartCarb).energyShare,
        closeTo(1, 1e-9),
      );
      expect(summary.contributionFor(PlateSegment.protein).energyShare, 0);
    });
  });

  group('complete plate', () {
    final NutritionalSummary summary = _summaryOf(<IngredientOption>[
      MawzoonCatalog.herbGrilledBreast,
      MawzoonCatalog.airFriedSpicedPotatoes,
      MawzoonCatalog.charredGardenVeggies,
    ]);

    test('is complete with nothing left to choose', () {
      expect(summary.isComplete, isTrue);
      expect(summary.remainingSegmentCount, 0);
      expect(summary.nextSegment, isNull);
    });

    test('segment energy shares sum to exactly one', () {
      final double total = PlateSegment.values
          .map((PlateSegment s) => summary.contributionFor(s).energyShare)
          .reduce((double a, double b) => a + b);
      expect(total, closeTo(1, 1e-9));
    });

    test('macronutrient energy shares sum to one', () {
      expect(
        summary.proteinEnergyShare +
            summary.carbohydrateEnergyShare +
            summary.fatEnergyShare,
        closeTo(1, 1e-9),
      );
    });

    test('total energy equals the sum of its compartments', () {
      final double parts = PlateSegment.values
          .map((PlateSegment s) => summary.contributionFor(s).kilocalories)
          .reduce((double a, double b) => a + b);
      expect(summary.totalKilocalories, closeTo(parts, 1e-9));
    });

    test('total mass equals the sum of its portions', () {
      expect(
        summary.totalPortionGrams,
        closeTo(
          MawzoonCatalog.herbGrilledBreast.basePortionGrams +
              MawzoonCatalog.airFriedSpicedPotatoes.basePortionGrams +
              MawzoonCatalog.charredGardenVeggies.basePortionGrams,
          1e-9,
        ),
      );
    });
  });

  group('scaling', () {
    test('Athletic Load grows protein and carb more than greens', () {
      final NutritionalSummary standard = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.herbGrilledBreast,
          MawzoonCatalog.airFriedSpicedPotatoes,
          MawzoonCatalog.charredGardenVeggies,
        ],
      );
      final NutritionalSummary athletic = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.herbGrilledBreast,
          MawzoonCatalog.airFriedSpicedPotatoes,
          MawzoonCatalog.charredGardenVeggies,
        ],
        scale: PortionScale.athleticLoad,
      );

      double ratio(NutritionalSummary a, NutritionalSummary b, PlateSegment s) =>
          b.contributionFor(s).portionGrams / a.contributionFor(s).portionGrams;

      expect(ratio(standard, athletic, PlateSegment.protein), closeTo(1.6, 1e-9));
      expect(ratio(standard, athletic, PlateSegment.smartCarb), closeTo(1.5, 1e-9));
      expect(ratio(standard, athletic, PlateSegment.vitalFiber), closeTo(1.15, 1e-9));
      expect(
        athletic.totalKilocalories,
        greaterThan(standard.totalKilocalories),
      );
    });

    test('the protein compartment gains share under Athletic Load', () {
      final NutritionalSummary standard = _summaryOf(<IngredientOption>[
        MawzoonCatalog.herbGrilledBreast,
        MawzoonCatalog.airFriedSpicedPotatoes,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      final NutritionalSummary athletic = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.herbGrilledBreast,
          MawzoonCatalog.airFriedSpicedPotatoes,
          MawzoonCatalog.charredGardenVeggies,
        ],
        scale: PortionScale.athleticLoad,
      );

      expect(
        athletic.contributionFor(PlateSegment.protein).energyShare,
        greaterThan(standard.contributionFor(PlateSegment.protein).energyShare),
      );
    });
  });

  group('allergens and dietary tags', () {
    test('allergens are the union across filled compartments', () {
      // Gluten is the only allergen this menu declares — it comes from the
      // two wheat carbs and nowhere else.
      final NutritionalSummary withGluten = _summaryOf(<IngredientOption>[
        MawzoonCatalog.smashedLeanBeef,
        MawzoonCatalog.wholeBulgur,
        MawzoonCatalog.mediterraneanSumacSalad,
      ]);
      expect(withGluten.allergens, <Allergen>{Allergen.gluten});

      final NutritionalSummary clean = _summaryOf(<IngredientOption>[
        MawzoonCatalog.smashedLeanBeef,
        MawzoonCatalog.toastedQuinoa,
        MawzoonCatalog.mediterraneanSumacSalad,
      ]);
      expect(clean.allergens, isEmpty);
    });

    test('an empty allergen set is a positive assertion, not missing data', () {
      // Every component is screened; a clean plate means screened and clear.
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(option.allergens, isNotNull, reason: option.id);
      }
      expect(
        MawzoonCatalog.all
            .where((IngredientOption o) => o.allergens.isNotEmpty)
            .map((IngredientOption o) => o.id),
        <String>['carb.whole_bulgur', 'carb.whole_wheat_pasta'],
      );
    });

    test('a tag describes the plate only if every compartment carries it', () {
      // One wheat carb is enough to take gluten-free off the whole plate.
      final NutritionalSummary withBulgur = _summaryOf(<IngredientOption>[
        MawzoonCatalog.koftaSpicedMince,
        MawzoonCatalog.wholeBulgur,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      expect(withBulgur.dietaryTags, isNot(contains(DietaryTag.glutenFree)));

      final NutritionalSummary allGlutenFree = _summaryOf(<IngredientOption>[
        MawzoonCatalog.koftaSpicedMince,
        MawzoonCatalog.toastedQuinoa,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      expect(allGlutenFree.dietaryTags, contains(DietaryTag.glutenFree));
      expect(allGlutenFree.dietaryTags, contains(DietaryTag.dairyFree));
    });

    test('no complete plate is plant-based, because no protein is', () {
      final NutritionalSummary plate = _summaryOf(<IngredientOption>[
        MawzoonCatalog.pulledSlowCookedBeef,
        MawzoonCatalog.sweetPotatoWedges,
        MawzoonCatalog.mediterraneanSumacSalad,
      ]);
      expect(plate.dietaryTags, isNot(contains(DietaryTag.plantBased)));

      // The carb and fibre compartments on their own still are.
      final NutritionalSummary sides = _summaryOf(<IngredientOption>[
        MawzoonCatalog.sweetPotatoWedges,
        MawzoonCatalog.mediterraneanSumacSalad,
      ]);
      expect(sides.dietaryTags, contains(DietaryTag.plantBased));
    });
  });

  group('glycemic engine', () {
    test('an empty plate has no load and no divide-by-zero', () {
      final NutritionalSummary empty =
          NutritionalSummary.empty(PortionScale.standardBalance);
      expect(empty.glycemic.load, 0);
      expect(empty.glycemic.dampedLoad, 0);
      expect(empty.glycemic.dampingFraction, 0);
    });

    test('protein alone contributes no glycemic load', () {
      final NutritionalSummary meatOnly =
          _summaryOf(<IngredientOption>[MawzoonCatalog.smokedEntrecote]);
      expect(meatOnly.glycemic.load, 0);
      expect(meatOnly.glycemic.balance, GlycemicBalance.steady);
    });

    test('plate load is the sum of its compartments', () {
      final NutritionalSummary summary = _summaryOf(<IngredientOption>[
        MawzoonCatalog.herbGrilledBreast,
        MawzoonCatalog.airFriedSpicedPotatoes,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      final double parts = PlateSegment.values
          .map((PlateSegment s) => summary.contributionFor(s).glycemicLoad)
          .reduce((double a, double b) => a + b);
      expect(summary.glycemic.load, closeTo(parts, 1e-9));
    });

    test('a high-GI carb lands the plate above a low-GI one', () {
      double loadWith(CarbOption carb) => _summaryOf(<IngredientOption>[
            MawzoonCatalog.herbGrilledBreast,
            carb,
            MawzoonCatalog.charredGardenVeggies,
          ]).glycemic.load;

      expect(
        loadWith(MawzoonCatalog.airFriedSpicedPotatoes),
        greaterThan(loadWith(MawzoonCatalog.wholeWheatPasta)),
      );
    });

    test('the rest of the plate damps the load, but only so far', () {
      final NutritionalSummary summary = _summaryOf(<IngredientOption>[
        MawzoonCatalog.herbGrilledBreast,
        MawzoonCatalog.airFriedSpicedPotatoes,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      expect(summary.glycemic.dampedLoad, lessThan(summary.glycemic.load));
      expect(
        summary.glycemic.dampingFraction,
        lessThanOrEqualTo(GlycemicProfile.maxDampingFraction + 1e-9),
      );
    });

    test('the published load is always kept alongside the adjusted one', () {
      final NutritionalSummary summary = _summaryOf(<IngredientOption>[
        MawzoonCatalog.herbGrilledBreast,
        MawzoonCatalog.steamedBasmati,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      // The figure shown to a guest is the standard metric, not the heuristic.
      expect(summary.glycemic.displayLoad, summary.glycemic.load.round());
      expect(summary.glycemic.displayDampedLoad,
          summary.glycemic.dampedLoad.round(),);
    });

    test('banding follows the published meal-level thresholds', () {
      expect(GlycemicProfile.classify(0), GlycemicBalance.steady);
      expect(GlycemicProfile.classify(10), GlycemicBalance.steady);
      expect(GlycemicProfile.classify(10.1), GlycemicBalance.balanced);
      expect(GlycemicProfile.classify(19), GlycemicBalance.balanced);
      expect(GlycemicProfile.classify(19.1), GlycemicBalance.quick);
      expect(GlycemicProfile.classify(40), GlycemicBalance.quick);
    });

    test('load rises with the portion', () {
      final NutritionalSummary standard = _summaryOf(<IngredientOption>[
        MawzoonCatalog.herbGrilledBreast,
        MawzoonCatalog.steamedBasmati,
        MawzoonCatalog.charredGardenVeggies,
      ]);
      final NutritionalSummary athletic = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.herbGrilledBreast,
          MawzoonCatalog.steamedBasmati,
          MawzoonCatalog.charredGardenVeggies,
        ],
        scale: PortionScale.athleticLoad,
      );
      expect(athletic.glycemic.load, greaterThan(standard.glycemic.load));
    });

    test('every band carries bilingual copy', () {
      for (final GlycemicBalance b in GlycemicBalance.values) {
        expect(b.headline.ar.trim(), isNotEmpty);
        expect(b.headline.en.trim(), isNotEmpty);
        expect(b.detail.ar.trim(), isNotEmpty);
        expect(b.detail.en.trim(), isNotEmpty);
      }
    });
  });

  group('anti-guilt framing', () {
    test('classifies a plate without ever failing it', () {
      const BalanceBand band = BalanceBand.standard;

      expect(band.classify(300), PlateEnergyFraming.lighter);
      expect(band.classify(550), PlateEnergyFraming.balanced);
      expect(band.classify(900), PlateEnergyFraming.heartier);
    });

    test('band bounds are inclusive', () {
      const BalanceBand band = BalanceBand.standard;

      expect(band.lowerBoundKilocalories, 475);
      expect(band.upperBoundKilocalories, 625);
      expect(band.contains(475), isTrue);
      expect(band.contains(625), isTrue);
      expect(band.contains(474.9), isFalse);
    });

    test('nominal progress clamps rather than overshooting', () {
      final NutritionalSummary heavy = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.smashedLeanBeef,
          MawzoonCatalog.steamedBasmati,
          MawzoonCatalog.mediterraneanSumacSalad,
        ],
        scale: PortionScale.athleticLoad,
      );

      expect(heavy.nominalProgress, lessThanOrEqualTo(1.0));
      expect(heavy.nominalProgress, greaterThan(0.9));
    });
  });

  group('construction contract', () {
    test('rejects two components in the same compartment', () {
      expect(
        () => NutritionalSummary.fromComponents(
          scale: PortionScale.standardBalance,
          components: <PortionedComponent>[
            MawzoonCatalog.herbGrilledBreast
                .atScale(PortionScale.standardBalance),
            MawzoonCatalog.smashedLeanBeef
                .atScale(PortionScale.standardBalance),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a component portioned at a different scale', () {
      expect(
        () => NutritionalSummary.fromComponents(
          scale: PortionScale.standardBalance,
          components: <PortionedComponent>[
            MawzoonCatalog.herbGrilledBreast.atScale(PortionScale.athleticLoad),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
