import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/nutritional_summary.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_builder_state.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';

void main() {
  group('PlateSelection', () {
    test('files a component by its own type, not by the caller\'s claim', () {
      final PlateSelection selection = PlateSelection.empty
          .select(MawzoonCatalog.charredBroccolini)
          .select(MawzoonCatalog.herbedQuinoa)
          .select(MawzoonCatalog.zaatarShrimp);

      expect(selection.protein, MawzoonCatalog.zaatarShrimp);
      expect(selection.carb, MawzoonCatalog.herbedQuinoa);
      expect(selection.fiber, MawzoonCatalog.charredBroccolini);
      expect(selection.isComplete, isTrue);
    });

    test('selecting into an occupied compartment replaces, never stacks', () {
      final PlateSelection selection = PlateSelection.empty
          .select(MawzoonCatalog.flameSearedChicken)
          .select(MawzoonCatalog.herbGrilledSalmon);

      expect(selection.protein, MawzoonCatalog.herbGrilledSalmon);
      expect(selection.filledSegments, <PlateSegment>{PlateSegment.protein});
    });

    test('clear empties exactly one compartment', () {
      final PlateSelection full = PlateSelection.empty
          .select(MawzoonCatalog.flameSearedChicken)
          .select(MawzoonCatalog.saffronBasmati)
          .select(MawzoonCatalog.charredBroccolini);

      final PlateSelection cleared = full.clear(PlateSegment.smartCarb);
      expect(cleared.carb, isNull);
      expect(cleared.protein, MawzoonCatalog.flameSearedChicken);
      expect(cleared.fiber, MawzoonCatalog.charredBroccolini);
      expect(cleared.scale, full.scale);
    });

    test('nextSegment walks the canonical build order', () {
      PlateSelection selection = PlateSelection.empty;
      expect(selection.nextSegment, PlateSegment.protein);

      selection = selection.select(MawzoonCatalog.flameSearedChicken);
      expect(selection.nextSegment, PlateSegment.smartCarb);

      selection = selection.select(MawzoonCatalog.saffronBasmati);
      expect(selection.nextSegment, PlateSegment.vitalFiber);

      selection = selection.select(MawzoonCatalog.charredBroccolini);
      expect(selection.nextSegment, isNull);
    });

    test('toggling the scale keeps every component', () {
      final PlateSelection standard = PlateSelection.empty
          .select(MawzoonCatalog.flameSearedChicken)
          .select(MawzoonCatalog.saffronBasmati);
      final PlateSelection athletic = standard.toggleScale();

      expect(athletic.scale, PortionScale.athleticLoad);
      expect(athletic.protein, standard.protein);
      expect(athletic.carb, standard.carb);
      expect(athletic.toggleScale().scale, PortionScale.standardBalance);
    });

    test('surcharges accumulate across compartments', () {
      final PlateSelection selection = PlateSelection.empty
          .select(MawzoonCatalog.herbGrilledSalmon) // 700
          .select(MawzoonCatalog.saffronBasmati) // 0
          .select(MawzoonCatalog.charredBroccolini); // 0

      expect(selection.surchargeMinorUnits, 700);
    });

    test('is a value type', () {
      final PlateSelection a =
          PlateSelection.empty.select(MawzoonCatalog.flameSearedChicken);
      final PlateSelection b =
          PlateSelection.empty.select(MawzoonCatalog.flameSearedChicken);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(a.toggleScale())));
    });
  });

  group('PlateBuilderState.from', () {
    test('an untouched selection derives PlateEmpty', () {
      final PlateBuilderState state =
          PlateBuilderState.from(PlateSelection.empty);

      expect(state, isA<PlateEmpty>());
      expect(state.canCheckout, isFalse);
      expect(state.remainingSegmentCount, 3);
      expect(state.macros.totalKilocalories, 0);
    });

    test('one or two compartments derive PlateConfiguring', () {
      final PlateBuilderState one = PlateBuilderState.from(
        PlateSelection.empty.select(MawzoonCatalog.flameSearedChicken),
      );
      expect(one, isA<PlateConfiguring>());
      expect(one.canCheckout, isFalse);
      expect(one.remainingSegmentCount, 2);

      final PlateBuilderState two = PlateBuilderState.from(
        PlateSelection.empty
            .select(MawzoonCatalog.flameSearedChicken)
            .select(MawzoonCatalog.saffronBasmati),
      );
      expect(two, isA<PlateConfiguring>());
      expect(two.remainingSegmentCount, 1);
    });

    test('all three compartments derive PlateBalanced', () {
      final PlateBuilderState state = PlateBuilderState.from(
        PlateSelection.empty
            .select(MawzoonCatalog.flameSearedChicken)
            .select(MawzoonCatalog.saffronBasmati)
            .select(MawzoonCatalog.charredBroccolini),
      );

      expect(state, isA<PlateBalanced>());
      expect(state.canCheckout, isTrue);
      expect(state.remainingSegmentCount, 0);

      final PlateBalanced balanced = state as PlateBalanced;
      expect(balanced.protein, MawzoonCatalog.flameSearedChicken);
      expect(balanced.finalMacros.isComplete, isTrue);
    });

    test('round-trips back to the selection it came from', () {
      final PlateSelection original = PlateSelection.empty
          .select(MawzoonCatalog.spicedLambKofta)
          .select(MawzoonCatalog.pearlCouscous)
          .toggleScale();

      expect(PlateBuilderState.from(original).selection, original);
    });

    test('carries the scale through every state', () {
      const PlateSelection athleticEmpty =
          PlateSelection(scale: PortionScale.athleticLoad);
      expect(
        PlateBuilderState.from(athleticEmpty).scale,
        PortionScale.athleticLoad,
      );
      expect(
        PlateBuilderState.from(
          athleticEmpty.select(MawzoonCatalog.flameSearedChicken),
        ).scale,
        PortionScale.athleticLoad,
      );
    });
  });

  group('state invariants', () {
    test('PlateConfiguring rejects an empty plate', () {
      expect(
        () => PlateConfiguring(
          currentMacros:
              NutritionalSummary.empty(PortionScale.standardBalance),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('PlateConfiguring rejects a fully filled plate', () {
      expect(
        () => PlateConfiguring(
          protein: MawzoonCatalog.flameSearedChicken,
          carb: MawzoonCatalog.saffronBasmati,
          fiber: MawzoonCatalog.charredBroccolini,
          currentMacros:
              NutritionalSummary.empty(PortionScale.standardBalance),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
