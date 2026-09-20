import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/balance_band.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';

void main() {
  group('PortionScale', () {
    test('offers exactly two choices — a binary, never a slider', () {
      expect(PortionScale.values, hasLength(2));
    });

    test('the standard portion is the identity across all compartments', () {
      for (final PlateSegment segment in PlateSegment.values) {
        expect(
          PortionScale.standardBalance.factorFor(segment),
          1.0,
          reason: segment.name,
        );
      }
    });

    test('the athletic load grows every compartment, greens the least', () {
      const PortionScale load = PortionScale.athleticLoad;
      final double protein = load.factorFor(PlateSegment.protein);
      final double carb = load.factorFor(PlateSegment.smartCarb);
      final double fiber = load.factorFor(PlateSegment.vitalFiber);

      expect(protein, greaterThan(1.0));
      expect(carb, greaterThan(1.0));
      expect(fiber, greaterThan(1.0));
      expect(protein, greaterThan(carb));
      expect(carb, greaterThan(fiber));
    });

    test('toggling is an involution', () {
      for (final PortionScale scale in PortionScale.values) {
        expect(scale.toggled.toggled, scale);
        expect(scale.toggled, isNot(scale));
      }
    });

    test('nominal energies match the two advertised numbers', () {
      expect(PortionScale.standardBalance.nominalKilocalories, 550);
      expect(PortionScale.athleticLoad.nominalKilocalories, 780);
    });

    test('each scale has a band centred on its nominal', () {
      for (final PortionScale scale in PortionScale.values) {
        final BalanceBand band = BalanceBand.forScale(scale);
        expect(band.nominalKilocalories, scale.nominalKilocalories);
        expect(band.contains(scale.nominalKilocalories.toDouble()), isTrue);
      }
    });

    test('carries bilingual labels', () {
      for (final PortionScale scale in PortionScale.values) {
        expect(scale.label.ar.trim(), isNotEmpty);
        expect(scale.label.en.trim(), isNotEmpty);
      }
    });
  });

  group('PlateSegment', () {
    test('has exactly three compartments in canonical order', () {
      expect(PlateSegment.values, hasLength(3));
      expect(PlateSegment.buildOrder, <PlateSegment>[
        PlateSegment.protein,
        PlateSegment.smartCarb,
        PlateSegment.vitalFiber,
      ]);
    });

    test('ordinals match the build order', () {
      for (int i = 0; i < PlateSegment.buildOrder.length; i++) {
        expect(PlateSegment.buildOrder[i].ordinal, i);
      }
    });

    test('every compartment has a bilingual label and invitation', () {
      for (final PlateSegment segment in PlateSegment.values) {
        expect(segment.label.ar.trim(), isNotEmpty, reason: segment.name);
        expect(segment.label.en.trim(), isNotEmpty, reason: segment.name);
        expect(segment.invitation.ar.trim(), isNotEmpty, reason: segment.name);
        expect(segment.invitation.en.trim(), isNotEmpty, reason: segment.name);
      }
    });
  });
}
