import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/balance_band.dart';
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
          _summaryOf(<IngredientOption>[MawzoonCatalog.flameSearedChicken]);

      expect(summary.isEmpty, isFalse);
      expect(summary.isComplete, isFalse);
      expect(summary.remainingSegmentCount, 2);
      expect(summary.nextSegment, PlateSegment.smartCarb);
      expect(summary.filledSegments, <PlateSegment>{PlateSegment.protein});
    });

    test('a single component owns the entire energy share', () {
      final NutritionalSummary summary =
          _summaryOf(<IngredientOption>[MawzoonCatalog.saffronBasmati]);

      expect(
        summary.contributionFor(PlateSegment.smartCarb).energyShare,
        closeTo(1, 1e-9),
      );
      expect(summary.contributionFor(PlateSegment.protein).energyShare, 0);
    });
  });

  group('complete plate', () {
    final NutritionalSummary summary = _summaryOf(<IngredientOption>[
      MawzoonCatalog.flameSearedChicken,
      MawzoonCatalog.airFriedSpicedPotatoes,
      MawzoonCatalog.charredBroccolini,
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
        closeTo(150 + 160 + 110, 1e-9),
      );
    });
  });

  group('scaling', () {
    test('Athletic Load grows protein and carb more than greens', () {
      final NutritionalSummary standard = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.flameSearedChicken,
          MawzoonCatalog.airFriedSpicedPotatoes,
          MawzoonCatalog.charredBroccolini,
        ],
      );
      final NutritionalSummary athletic = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.flameSearedChicken,
          MawzoonCatalog.airFriedSpicedPotatoes,
          MawzoonCatalog.charredBroccolini,
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
        MawzoonCatalog.flameSearedChicken,
        MawzoonCatalog.airFriedSpicedPotatoes,
        MawzoonCatalog.charredBroccolini,
      ]);
      final NutritionalSummary athletic = _summaryOf(
        <IngredientOption>[
          MawzoonCatalog.flameSearedChicken,
          MawzoonCatalog.airFriedSpicedPotatoes,
          MawzoonCatalog.charredBroccolini,
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
      final NutritionalSummary summary = _summaryOf(<IngredientOption>[
        MawzoonCatalog.herbGrilledSalmon, // fish
        MawzoonCatalog.freekehPilaf, // gluten
        MawzoonCatalog.blisteredGreenBeans, // tree nuts
      ]);

      expect(
        summary.allergens,
        <Allergen>{Allergen.fish, Allergen.gluten, Allergen.treeNuts},
      );
    });

    test('a tag describes the plate only if every compartment carries it', () {
      final NutritionalSummary mixed = _summaryOf(<IngredientOption>[
        MawzoonCatalog.spicedLambKofta, // not plant-based
        MawzoonCatalog.herbedQuinoa,
        MawzoonCatalog.charredBroccolini,
      ]);
      expect(mixed.dietaryTags, isNot(contains(DietaryTag.plantBased)));

      final NutritionalSummary vegan = _summaryOf(<IngredientOption>[
        MawzoonCatalog.smokedHarissaTofu,
        MawzoonCatalog.sweetPotatoMash,
        MawzoonCatalog.blisteredGreenBeans,
      ]);
      expect(vegan.dietaryTags, contains(DietaryTag.plantBased));
      expect(vegan.dietaryTags, contains(DietaryTag.glutenFree));
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
          MawzoonCatalog.herbGrilledSalmon,
          MawzoonCatalog.saffronBasmati,
          MawzoonCatalog.citrusFennelRocket,
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
            MawzoonCatalog.flameSearedChicken
                .atScale(PortionScale.standardBalance),
            MawzoonCatalog.herbGrilledSalmon
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
            MawzoonCatalog.flameSearedChicken.atScale(PortionScale.athleticLoad),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
