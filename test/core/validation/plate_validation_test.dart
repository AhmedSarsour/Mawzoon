import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/validation/plate_validation.dart';

/// Gluten is the only allergen this menu declares, and it comes from the two
/// wheat carbs. A coeliac guest is the concrete case the screening exists for.
const List<IngredientOption> _glutenPlate = <IngredientOption>[
  MawzoonCatalog.herbGrilledBreast,
  MawzoonCatalog.wholeBulgur,
  MawzoonCatalog.charredGardenVeggies,
];

const List<IngredientOption> _glutenFreePlate = <IngredientOption>[
  MawzoonCatalog.herbGrilledBreast,
  MawzoonCatalog.toastedQuinoa,
  MawzoonCatalog.charredGardenVeggies,
];

void main() {
  group('unrestricted guests', () {
    test('never see an advisory, whatever the plate', () {
      for (final ProteinOption protein in MawzoonCatalog.proteins) {
        for (final CarbOption carb in MawzoonCatalog.carbs) {
          final List<PlateAdvisory> advisories =
              PlateValidator.validate(components: <IngredientOption>[
            protein,
            carb,
            MawzoonCatalog.mediterraneanSumacSalad,
          ],);
          expect(advisories, isEmpty, reason: '${protein.id} + ${carb.id}');
        }
      }
    });

    test('can be served anything on the menu', () {
      expect(PlateValidator.isServable(components: _glutenPlate), isTrue);
    });
  });

  group('allergen screening is a hard stop', () {
    const GuestDietaryProfile coeliac = GuestDietaryProfile(
      avoidedAllergens: <Allergen>{Allergen.gluten},
    );

    test('blocks a plate carrying a declared allergen', () {
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: _glutenPlate,
        profile: coeliac,
      );

      expect(advisories, hasLength(1));
      expect(advisories.single.isBlocking, isTrue);
      expect(advisories.single.allergen, Allergen.gluten);
      expect(advisories.single.segment, PlateSegment.smartCarb);
      expect(
        PlateValidator.isServable(
          components: _glutenPlate,
          profile: coeliac,
        ),
        isFalse,
      );
    });

    test('names the offending dish in both languages', () {
      final PlateAdvisory advisory = PlateValidator.validate(
        components: _glutenPlate,
        profile: coeliac,
      ).single;

      expect(advisory.message.ar, contains(MawzoonCatalog.wholeBulgur.name.ar));
      expect(advisory.message.en, contains(MawzoonCatalog.wholeBulgur.name.en));
      expect(advisory.message.ar, contains(Allergen.gluten.label.ar));
      expect(advisory.message.en, contains(Allergen.gluten.label.en));
    });

    test('clears a plate that avoids the allergen', () {
      expect(
        PlateValidator.validate(
          components: _glutenFreePlate,
          profile: coeliac,
        ),
        isEmpty,
      );
    });

    test('four of the six carbs remain open to a coeliac guest', () {
      final Iterable<CarbOption> safe = MawzoonCatalog.carbs.where(
        (CarbOption c) => PlateValidator.isServable(
          components: <IngredientOption>[c],
          profile: coeliac,
        ),
      );
      expect(safe, hasLength(4));
      expect(safe, isNot(contains(MawzoonCatalog.wholeBulgur)));
      expect(safe, isNot(contains(MawzoonCatalog.wholeWheatPasta)));
    });

    test('raises one advisory per offending component', () {
      // Two wheat carbs cannot both be on one plate, so this exercises the
      // per-component loop directly rather than through a buildable plate.
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: <IngredientOption>[
          MawzoonCatalog.wholeBulgur,
          MawzoonCatalog.wholeWheatPasta,
        ],
        profile: coeliac,
      );

      expect(advisories, hasLength(2));
      expect(advisories.every((PlateAdvisory a) => a.isBlocking), isTrue);
    });

    test('an allergen the guest has not declared does not block', () {
      const GuestDietaryProfile nutAllergy = GuestDietaryProfile(
        avoidedAllergens: <Allergen>{Allergen.treeNuts},
      );
      expect(
        PlateValidator.isServable(components: _glutenPlate, profile: nutAllergy),
        isTrue,
      );
    });
  });

  group('dietary preferences are informational only', () {
    const GuestDietaryProfile prefersGlutenFree = GuestDietaryProfile(
      preferredTags: <DietaryTag>{DietaryTag.glutenFree},
    );

    test('a preference never blocks checkout', () {
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: _glutenPlate,
        profile: prefersGlutenFree,
      );

      expect(advisories, hasLength(1));
      expect(advisories.single.isBlocking, isFalse);
      expect(advisories.single.severity, PlateAdvisorySeverity.informational);
      expect(
        PlateValidator.isServable(
          components: _glutenPlate,
          profile: prefersGlutenFree,
        ),
        isTrue,
      );
    });

    test('a fully compliant plate raises nothing', () {
      expect(
        PlateValidator.validate(
          components: _glutenFreePlate,
          profile: prefersGlutenFree,
        ),
        isEmpty,
      );
    });

    test('the note names every non-compliant component, in both languages', () {
      const GuestDietaryProfile prefersPlantBased = GuestDietaryProfile(
        preferredTags: <DietaryTag>{DietaryTag.plantBased},
      );
      final PlateAdvisory advisory = PlateValidator.validate(
        components: _glutenFreePlate,
        profile: prefersPlantBased,
      ).single;

      // No protein on this menu is plant-based, so the breast is the only
      // component that can be named.
      expect(
        advisory.message.en,
        contains(MawzoonCatalog.herbGrilledBreast.name.en),
      );
      expect(
        advisory.message.ar,
        contains(MawzoonCatalog.herbGrilledBreast.name.ar),
      );
      expect(
        advisory.message.en,
        isNot(contains(MawzoonCatalog.toastedQuinoa.name.en)),
      );
    });
  });

  group('ordering', () {
    test('blocking advisories come first', () {
      const GuestDietaryProfile profile = GuestDietaryProfile(
        avoidedAllergens: <Allergen>{Allergen.gluten},
        preferredTags: <DietaryTag>{DietaryTag.plantBased},
      );
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: _glutenPlate,
        profile: profile,
      );

      expect(advisories.length, greaterThanOrEqualTo(2));
      expect(advisories.first.isBlocking, isTrue);
      expect(advisories.last.isBlocking, isFalse);
    });

    test('an unrestricted profile reports itself as such', () {
      expect(GuestDietaryProfile.unrestricted.isUnrestricted, isTrue);
      expect(
        const GuestDietaryProfile(
          avoidedAllergens: <Allergen>{Allergen.egg},
        ).isUnrestricted,
        isFalse,
      );
    });
  });
}
