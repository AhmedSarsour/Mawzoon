import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';

void main() {
  group('catalogue shape', () {
    test('ships six proteins, six smart carbs and two vital fibres', () {
      expect(MawzoonCatalog.proteins, hasLength(6));
      expect(MawzoonCatalog.carbs, hasLength(6));
      expect(MawzoonCatalog.fibers, hasLength(2));
      expect(MawzoonCatalog.all, hasLength(14));
    });

    test('offers 72 buildable plates', () {
      expect(
        MawzoonCatalog.proteins.length *
            MawzoonCatalog.carbs.length *
            MawzoonCatalog.fibers.length,
        72,
      );
    });

    test('every identifier is unique', () {
      final List<String> ids =
          MawzoonCatalog.all.map((IngredientOption o) => o.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('identifiers are namespaced by compartment', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final String prefix = switch (option.segment) {
          PlateSegment.protein => 'protein.',
          PlateSegment.smartCarb => 'carb.',
          PlateSegment.vitalFiber => 'fiber.',
        };
        expect(option.id, startsWith(prefix), reason: option.id);
      }
    });

    test('optionsFor returns the right compartment', () {
      expect(
        MawzoonCatalog.optionsFor(PlateSegment.protein),
        MawzoonCatalog.proteins,
      );
      expect(
        MawzoonCatalog.optionsFor(PlateSegment.smartCarb),
        MawzoonCatalog.carbs,
      );
      expect(
        MawzoonCatalog.optionsFor(PlateSegment.vitalFiber),
        MawzoonCatalog.fibers,
      );
    });

    test('lookup finds known ids and refuses unknown ones', () {
      expect(
        MawzoonCatalog.optionById('protein.herb_grilled_breast'),
        MawzoonCatalog.herbGrilledBreast,
      );
      expect(MawzoonCatalog.optionById('protein.not_on_the_menu'), isNull);
      expect(MawzoonCatalog.carbById('carb.toasted_quinoa'),
          MawzoonCatalog.toastedQuinoa,);
      // A carb id must not resolve through the protein lookup.
      expect(MawzoonCatalog.proteinById('carb.toasted_quinoa'), isNull);
    });
  });

  group('bilingual completeness', () {
    test('every component has non-empty Arabic and English copy', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(option.name.ar.trim(), isNotEmpty, reason: option.id);
        expect(option.name.en.trim(), isNotEmpty, reason: option.id);
        expect(option.description.ar.trim(), isNotEmpty, reason: option.id);
        expect(option.description.en.trim(), isNotEmpty, reason: option.id);
      }
    });

    test('Arabic copy actually contains Arabic script', () {
      final RegExp arabic = RegExp(r'[؀-ۿ]');
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(arabic.hasMatch(option.name.ar), isTrue, reason: option.id);
        expect(arabic.hasMatch(option.description.ar), isTrue, reason: option.id);
      }
    });
  });

  group('nutritional integrity', () {
    test('every portion has positive mass and positive energy', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(option.basePortionGrams, greaterThan(0), reason: option.id);
        expect(option.baseKilocalories, greaterThan(0), reason: option.id);
      }
    });

    test('fibre never exceeds the carbohydrate it is a subset of', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(
          option.baseMacros.dietaryFiberGrams,
          lessThanOrEqualTo(option.baseMacros.carbohydrateGrams),
          reason: option.id,
        );
      }
    });

    test('macronutrient mass never exceeds the plated mass', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final double macroMass = option.baseMacros.proteinGrams +
            option.baseMacros.carbohydrateGrams +
            option.baseMacros.fatGrams;
        expect(
          macroMass,
          lessThanOrEqualTo(option.basePortionGrams),
          reason: '${option.id} claims more macronutrient mass than it weighs',
        );
      }
    });

    test('proteins actually lead on protein', () {
      for (final ProteinOption protein in MawzoonCatalog.proteins) {
        expect(
          protein.baseMacros.proteinKilocalories /
              protein.baseMacros.kilocalories,
          greaterThan(0.4),
          reason: '${protein.id} should be protein-dominant by energy',
        );
      }
    });

    test('smart carbs actually lead on carbohydrate', () {
      for (final CarbOption carb in MawzoonCatalog.carbs) {
        expect(
          carb.baseMacros.carbohydrateKilocalories /
              carb.baseMacros.kilocalories,
          greaterThan(0.5),
          reason: '${carb.id} should be carbohydrate-dominant by energy',
        );
      }
    });

    test('vital fibres are genuinely fibrous and light', () {
      for (final FiberOption fiber in MawzoonCatalog.fibers) {
        expect(fiber.baseMacros.dietaryFiberGrams, greaterThanOrEqualTo(3),
            reason: fiber.id,);
        expect(fiber.baseKilocalories, lessThan(120), reason: fiber.id);
      }
    });
  });

  group('glycemic data', () {
    test('every carbohydrate-bearing component declares a glycemic index', () {
      for (final IngredientOption option in <IngredientOption>[
        ...MawzoonCatalog.carbs,
        ...MawzoonCatalog.fibers,
      ]) {
        expect(option.glycemicIndex, greaterThan(0), reason: option.id);
        expect(option.glycemicIndex, lessThanOrEqualTo(110), reason: option.id);
      }
    });

    test('proteins carry no index, because the measure is undefined for them',
        () {
      for (final ProteinOption protein in MawzoonCatalog.proteins) {
        expect(protein.glycemicIndex, 0, reason: protein.id);
        expect(protein.baseGlycemicLoad, 0, reason: protein.id);
      }
    });

    test('greens sit far below any grain', () {
      final int highestFiber = MawzoonCatalog.fibers
          .map((FiberOption f) => f.glycemicIndex)
          .reduce((int a, int b) => a > b ? a : b);
      final int lowestCarb = MawzoonCatalog.carbs
          .map((CarbOption c) => c.glycemicIndex)
          .reduce((int a, int b) => a < b ? a : b);
      expect(highestFiber, lessThan(lowestCarb));
    });

    test('glycemic load weights the index by digestible carbohydrate', () {
      const CarbOption basmati = MawzoonCatalog.steamedBasmati;
      expect(
        basmati.baseGlycemicLoad,
        closeTo(
          basmati.glycemicIndex *
              basmati.baseMacros.netCarbohydrateGrams /
              100,
          1e-9,
        ),
      );
      // Basmati carries more carbohydrate than bulgur but a similar index, so
      // load — not index — is what separates them on a plate.
      expect(
        basmati.baseGlycemicLoad,
        greaterThan(MawzoonCatalog.wholeBulgur.baseGlycemicLoad),
      );
    });

    test('load scales with the portion, because index is per food not per gram',
        () {
      const CarbOption potatoes = MawzoonCatalog.airFriedSpicedPotatoes;
      final PortionedComponent athletic =
          potatoes.atScale(PortionScale.athleticLoad);
      expect(
        athletic.glycemicLoad,
        closeTo(
          potatoes.baseGlycemicLoad *
              PortionScale.athleticLoad.factorFor(PlateSegment.smartCarb),
          1e-9,
        ),
      );
    });
  });

  group('safety and tag consistency', () {
    test('a gluten-free component declares no gluten allergen', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        if (!option.dietaryTags.contains(DietaryTag.glutenFree)) continue;
        expect(option.allergens, isNot(contains(Allergen.gluten)),
            reason: option.id,);
      }
    });

    test('a dairy-free component declares no dairy allergen', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        if (!option.dietaryTags.contains(DietaryTag.dairyFree)) continue;
        expect(option.allergens, isNot(contains(Allergen.dairy)),
            reason: option.id,);
      }
    });

    test('no protein is plant-based — the anchor menu is entirely meat', () {
      // Recorded as a property, not an oversight. If a plant protein is added
      // this test fails and whoever adds it revisits the plant-based plate
      // story deliberately.
      for (final ProteinOption protein in MawzoonCatalog.proteins) {
        expect(protein.dietaryTags, isNot(contains(DietaryTag.plantBased)),
            reason: protein.id,);
      }
    });

    test('every carb and every fibre is plant-based', () {
      for (final IngredientOption option in <IngredientOption>[
        ...MawzoonCatalog.carbs,
        ...MawzoonCatalog.fibers,
      ]) {
        expect(option.dietaryTags, contains(DietaryTag.plantBased),
            reason: option.id,);
      }
    });

    test('a plant-based component carries no animal allergen and is dairy-free',
        () {
      const Set<Allergen> animal = <Allergen>{
        Allergen.dairy,
        Allergen.fish,
        Allergen.shellfish,
        Allergen.egg,
      };
      for (final IngredientOption option in MawzoonCatalog.all) {
        if (!option.dietaryTags.contains(DietaryTag.plantBased)) continue;
        expect(option.allergens.intersection(animal), isEmpty,
            reason: option.id,);
        expect(option.dietaryTags, contains(DietaryTag.dairyFree),
            reason: option.id,);
      }
    });

    test('the high-protein tag means at least 30 g in the standard portion', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final bool tagged = option.dietaryTags.contains(DietaryTag.highProtein);
        final bool qualifies = option.baseMacros.proteinGrams >= 30;
        expect(tagged, qualifies,
            reason: '${option.id}: tag says $tagged, grams say $qualifies',);
      }
    });

    test('the low-carb tag means under 15 g of digestible carbohydrate', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final bool tagged = option.dietaryTags.contains(DietaryTag.lowCarb);
        final bool qualifies = option.baseMacros.netCarbohydrateGrams < 15;
        expect(tagged, qualifies,
            reason: '${option.id}: tag says $tagged, grams say $qualifies',);
      }
    });

    test('surcharges are never negative', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        expect(option.surchargeMinorUnits, greaterThanOrEqualTo(0),
            reason: option.id,);
      }
    });
  });

  group('portion resolution', () {
    test('atScale keeps mass and macros in lockstep', () {
      const ProteinOption chicken = MawzoonCatalog.herbGrilledBreast;
      final PortionedComponent athletic =
          chicken.atScale(PortionScale.athleticLoad);
      final double factor =
          PortionScale.athleticLoad.factorFor(PlateSegment.protein);

      expect(athletic.portionGrams,
          closeTo(chicken.basePortionGrams * factor, 1e-9),);
      expect(athletic.macros.proteinGrams,
          closeTo(chicken.baseMacros.proteinGrams * factor, 1e-9),);
      expect(athletic.kilocalories,
          closeTo(chicken.baseKilocalories * factor, 1e-9),);
      expect(athletic.segment, PlateSegment.protein);
    });

    test('the standard scale is the identity', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final PortionedComponent standard =
            option.atScale(PortionScale.standardBalance);
        expect(standard.portionGrams, closeTo(option.basePortionGrams, 1e-9));
        expect(standard.macros, option.baseMacros);
      }
    });
  });
}
