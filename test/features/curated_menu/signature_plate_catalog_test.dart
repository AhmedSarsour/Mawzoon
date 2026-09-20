import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/balance_band.dart';
import 'package:mawzoon/core/nutrition/nutritional_summary.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/curated_menu/data/signature_plate_catalog.dart';
import 'package:mawzoon/features/curated_menu/domain/signature_plate.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_builder_state.dart';

void main() {
  group('curated menu shape', () {
    test('ships six signature plates with unique ids', () {
      expect(SignaturePlateCatalog.all, hasLength(6));
      final List<String> ids =
          SignaturePlateCatalog.all.map((SignaturePlate p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every component comes from the component catalogue', () {
      for (final SignaturePlate plate in SignaturePlateCatalog.all) {
        expect(MawzoonCatalog.proteins, contains(plate.protein),
            reason: plate.id,);
        expect(MawzoonCatalog.carbs, contains(plate.carb), reason: plate.id);
        expect(MawzoonCatalog.fibers, contains(plate.fiber), reason: plate.id);
      }
    });

    test('lookup finds known ids and refuses unknown ones', () {
      expect(
        SignaturePlateCatalog.byId('signature.ember_standard'),
        SignaturePlateCatalog.emberStandard,
      );
      expect(SignaturePlateCatalog.byId('signature.nope'), isNull);
    });

    test('every plate carries complete bilingual copy', () {
      final RegExp arabic = RegExp(r'[؀-ۿ]');
      for (final SignaturePlate plate in SignaturePlateCatalog.all) {
        expect(plate.name.ar.trim(), isNotEmpty, reason: plate.id);
        expect(plate.name.en.trim(), isNotEmpty, reason: plate.id);
        expect(plate.tagline.ar.trim(), isNotEmpty, reason: plate.id);
        expect(plate.chefNote.ar.trim(), isNotEmpty, reason: plate.id);
        expect(arabic.hasMatch(plate.name.ar), isTrue, reason: plate.id);
        expect(arabic.hasMatch(plate.chefNote.ar), isTrue, reason: plate.id);
      }
    });

    test('no signature plate is plant-based, because no protein is', () {
      // Recorded rather than wished away: the anchor menu is entirely meat, so
      // the curated track cannot offer a vegan plate. If a plant protein is
      // ever added, this test fails and the gap gets filled on purpose.
      final Iterable<SignaturePlate> plantBased = SignaturePlateCatalog.all
          .where(
            (SignaturePlate p) => p
                .summaryAt(PortionScale.standardBalance)
                .dietaryTags
                .contains(DietaryTag.plantBased),
          );
      expect(plantBased, isEmpty);
    });

    test('the six plates tour the whole menu rather than repeat components',
        () {
      expect(
        SignaturePlateCatalog.all
            .map((SignaturePlate p) => p.protein.id)
            .toSet(),
        hasLength(6),
      );
      expect(
        SignaturePlateCatalog.all.map((SignaturePlate p) => p.carb.id).toSet(),
        hasLength(6),
      );
      expect(
        SignaturePlateCatalog.all.map((SignaturePlate p) => p.fiber.id).toSet(),
        hasLength(2),
      );
    });

    test('at least one plate is gluten-free end to end', () {
      final Iterable<SignaturePlate> glutenFree = SignaturePlateCatalog.all
          .where(
            (SignaturePlate p) => p
                .summaryAt(PortionScale.standardBalance)
                .dietaryTags
                .contains(DietaryTag.glutenFree),
          );
      expect(glutenFree, isNotEmpty);
    });
  });

  // The contract that makes the Curated Track trustworthy: a guest who taps a
  // signature plate and never opens the Architect must still land inside the
  // house band at whichever portion they chose.
  group('every signature plate lands inside its house band', () {
    for (final SignaturePlate plate in SignaturePlateCatalog.all) {
      for (final PortionScale scale in PortionScale.values) {
        test('${plate.id} at ${scale.name}', () {
          final NutritionalSummary summary = plate.summaryAt(scale);
          final BalanceBand band = BalanceBand.forScale(scale);

          expect(summary.isComplete, isTrue);
          expect(
            band.contains(summary.totalKilocalories),
            isTrue,
            reason: '${plate.id} at ${scale.name} is '
                '${summary.totalKilocalories.toStringAsFixed(1)} kcal, outside '
                '${band.lowerBoundKilocalories}–${band.upperBoundKilocalories}',
          );
          expect(summary.framing, PlateEnergyFraming.balanced);
        });
      }
    }
  });

  group('signature plates are protein-forward', () {
    for (final SignaturePlate plate in SignaturePlateCatalog.all) {
      test('${plate.id} clears 30 g of protein at the standard portion', () {
        final NutritionalSummary summary =
            plate.summaryAt(PortionScale.standardBalance);
        expect(summary.totalMacros.proteinGrams, greaterThanOrEqualTo(30),
            reason: plate.id,);
      });
    }
  });

  group('curated to custom handoff', () {
    test('a signature plate opens in the Architect already balanced', () {
      for (final SignaturePlate plate in SignaturePlateCatalog.all) {
        final PlateBuilderState state = PlateBuilderState.from(
          plate.selectionAt(PortionScale.standardBalance),
        );
        expect(state, isA<PlateBalanced>(), reason: plate.id);
        expect(state.canCheckout, isTrue, reason: plate.id);
      }
    });

    test('the handoff preserves the chosen portion scale', () {
      const SignaturePlate plate = SignaturePlateCatalog.smokehouseBulgur;
      expect(
        plate.selectionAt(PortionScale.athleticLoad).scale,
        PortionScale.athleticLoad,
      );
      expect(
        plate.summaryAt(PortionScale.athleticLoad).scale,
        PortionScale.athleticLoad,
      );
    });
  });

  group('pricing', () {
    test('includes component surcharges', () {
      // The entrecote is the only surcharged component on this plate.
      expect(
        SignaturePlateCatalog.smokehouseBulgur
            .priceAt(PortionScale.standardBalance),
        4900 + MawzoonCatalog.smokedEntrecote.surchargeMinorUnits,
      );
      expect(
        SignaturePlateCatalog.emberStandard
            .priceAt(PortionScale.standardBalance),
        4900,
      );
    });

    test('the Athletic Load carries a flat uplift', () {
      for (final SignaturePlate plate in SignaturePlateCatalog.all) {
        final int standard = plate.priceAt(PortionScale.standardBalance);
        final int athletic = plate.priceAt(PortionScale.athleticLoad);
        expect(athletic - standard, 1500, reason: plate.id);
      }
    });

    test('every price is positive', () {
      for (final SignaturePlate plate in SignaturePlateCatalog.all) {
        for (final PortionScale scale in PortionScale.values) {
          expect(plate.priceAt(scale), greaterThan(0), reason: plate.id);
        }
      }
    });
  });

  group('glycemic reading', () {
    for (final SignaturePlate plate in SignaturePlateCatalog.all) {
      test('${plate.id} reports a load below its raw figure', () {
        final NutritionalSummary summary =
            plate.summaryAt(PortionScale.standardBalance);
        expect(summary.glycemic.load, greaterThan(0));
        expect(
          summary.glycemic.dampedLoad,
          lessThanOrEqualTo(summary.glycemic.load),
        );
      });
    }

    test('the wheat-carb plates release more slowly than the potato one', () {
      double loadOf(SignaturePlate p) =>
          p.summaryAt(PortionScale.standardBalance).glycemic.load;

      expect(
        loadOf(SignaturePlateCatalog.koftaAlDente),
        lessThan(loadOf(SignaturePlateCatalog.emberStandard)),
      );
      expect(
        loadOf(SignaturePlateCatalog.smokehouseBulgur),
        lessThan(loadOf(SignaturePlateCatalog.smashAndSteam)),
      );
    });
  });
}
