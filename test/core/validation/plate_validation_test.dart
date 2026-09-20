import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/validation/plate_validation.dart';

const List<IngredientOption> _shellfishPlate = <IngredientOption>[
  MawzoonCatalog.zaatarShrimp,
  MawzoonCatalog.herbedQuinoa,
  MawzoonCatalog.citrusFennelRocket,
];

const List<IngredientOption> _safePlate = <IngredientOption>[
  MawzoonCatalog.flameSearedChicken,
  MawzoonCatalog.sweetPotatoMash,
  MawzoonCatalog.charredBroccolini,
];

void main() {
  group('unrestricted guests', () {
    test('never see an advisory', () {
      for (final IngredientOption protein in MawzoonCatalog.proteins) {
        final List<PlateAdvisory> advisories = PlateValidator.validate(
          components: <IngredientOption>[
            protein,
            MawzoonCatalog.freekehPilaf,
            MawzoonCatalog.blisteredGreenBeans,
          ],
        );
        expect(advisories, isEmpty, reason: protein.id);
      }
    });

    test('can be served anything on the menu', () {
      expect(PlateValidator.isServable(components: _shellfishPlate), isTrue);
    });
  });

  group('allergen screening is a hard stop', () {
    const GuestDietaryProfile shellfishAllergy = GuestDietaryProfile(
      avoidedAllergens: <Allergen>{Allergen.shellfish},
    );

    test('blocks a plate carrying a declared allergen', () {
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: _shellfishPlate,
        profile: shellfishAllergy,
      );

      expect(advisories, hasLength(1));
      expect(advisories.single.isBlocking, isTrue);
      expect(advisories.single.allergen, Allergen.shellfish);
      expect(advisories.single.segment, PlateSegment.protein);
      expect(
        PlateValidator.isServable(
          components: _shellfishPlate,
          profile: shellfishAllergy,
        ),
        isFalse,
      );
    });

    test('names the offending dish in both languages', () {
      final PlateAdvisory advisory = PlateValidator.validate(
        components: _shellfishPlate,
        profile: shellfishAllergy,
      ).single;

      expect(advisory.message.ar, contains(MawzoonCatalog.zaatarShrimp.name.ar));
      expect(advisory.message.en, contains(MawzoonCatalog.zaatarShrimp.name.en));
      expect(advisory.message.ar, contains(Allergen.shellfish.label.ar));
      expect(advisory.message.en, contains(Allergen.shellfish.label.en));
    });

    test('clears a plate that avoids the allergen', () {
      expect(
        PlateValidator.validate(
          components: _safePlate,
          profile: shellfishAllergy,
        ),
        isEmpty,
      );
    });

    test('raises one advisory per offending component', () {
      const GuestDietaryProfile multiple = GuestDietaryProfile(
        avoidedAllergens: <Allergen>{Allergen.gluten, Allergen.treeNuts},
      );
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: <IngredientOption>[
          MawzoonCatalog.flameSearedChicken,
          MawzoonCatalog.freekehPilaf, // gluten
          MawzoonCatalog.blisteredGreenBeans, // tree nuts
        ],
        profile: multiple,
      );

      expect(advisories, hasLength(2));
      expect(advisories.every((PlateAdvisory a) => a.isBlocking), isTrue);
    });
  });

  group('dietary preferences are informational only', () {
    const GuestDietaryProfile vegan = GuestDietaryProfile(
      preferredTags: <DietaryTag>{DietaryTag.plantBased},
    );

    test('a preference never blocks checkout', () {
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: _safePlate,
        profile: vegan,
      );

      expect(advisories, hasLength(1));
      expect(advisories.single.isBlocking, isFalse);
      expect(
        advisories.single.severity,
        PlateAdvisorySeverity.informational,
      );
      expect(
        PlateValidator.isServable(components: _safePlate, profile: vegan),
        isTrue,
      );
    });

    test('a fully compliant plate raises nothing', () {
      expect(
        PlateValidator.validate(
          components: <IngredientOption>[
            MawzoonCatalog.smokedHarissaTofu,
            MawzoonCatalog.sweetPotatoMash,
            MawzoonCatalog.blisteredGreenBeans,
          ],
          profile: vegan,
        ),
        isEmpty,
      );
    });

    test('the note names every non-compliant component, in both languages', () {
      final PlateAdvisory advisory = PlateValidator.validate(
        components: <IngredientOption>[
          MawzoonCatalog.flameSearedChicken, // not plant-based
          MawzoonCatalog.saffronBasmati, // plant-based
          MawzoonCatalog.charredBroccolini, // plant-based
        ],
        profile: vegan,
      ).single;

      expect(
        advisory.message.en,
        contains(MawzoonCatalog.flameSearedChicken.name.en),
      );
      expect(
        advisory.message.ar,
        contains(MawzoonCatalog.flameSearedChicken.name.ar),
      );
      expect(
        advisory.message.en,
        isNot(contains(MawzoonCatalog.saffronBasmati.name.en)),
      );
    });
  });

  group('ordering', () {
    test('blocking advisories come first', () {
      const GuestDietaryProfile profile = GuestDietaryProfile(
        avoidedAllergens: <Allergen>{Allergen.treeNuts},
        preferredTags: <DietaryTag>{DietaryTag.plantBased},
      );
      final List<PlateAdvisory> advisories = PlateValidator.validate(
        components: <IngredientOption>[
          MawzoonCatalog.flameSearedChicken,
          MawzoonCatalog.sweetPotatoMash,
          MawzoonCatalog.blisteredGreenBeans,
        ],
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
