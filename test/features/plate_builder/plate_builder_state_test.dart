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
          .select(MawzoonCatalog.charredGardenVeggies)
          .select(MawzoonCatalog.toastedQuinoa)
          .select(MawzoonCatalog.marinatedThighs);

      expect(selection.protein, MawzoonCatalog.marinatedThighs);
      expect(selection.carb, MawzoonCatalog.toastedQuinoa);
      expect(selection.fiber, MawzoonCatalog.charredGardenVeggies);
      expect(selection.isComplete, isTrue);
    });

    test('selecting into an occupied compartment replaces, never stacks', () {
      final PlateSelection selection = PlateSelection.empty
          .select(MawzoonCatalog.herbGrilledBreast)
          .select(MawzoonCatalog.smashedLeanBeef);

      expect(selection.protein, MawzoonCatalog.smashedLeanBeef);
      expect(selection.filledSegments, <PlateSegment>{PlateSegment.protein});
    });

    test('clear empties exactly one compartment', () {
      final PlateSelection full = PlateSelection.empty
          .select(MawzoonCatalog.herbGrilledBreast)
          .select(MawzoonCatalog.steamedBasmati)
          .select(MawzoonCatalog.charredGardenVeggies);

      final PlateSelection cleared = full.clear(PlateSegment.smartCarb);
      expect(cleared.carb, isNull);
      expect(cleared.protein, MawzoonCatalog.herbGrilledBreast);
      expect(cleared.fiber, MawzoonCatalog.charredGardenVeggies);
      expect(cleared.scale, full.scale);
    });

    test('nextSegment walks the canonical build order', () {
      PlateSelection selection = PlateSelection.empty;
      expect(selection.nextSegment, PlateSegment.protein);

      selection = selection.select(MawzoonCatalog.herbGrilledBreast);
      expect(selection.nextSegment, PlateSegment.smartCarb);

      selection = selection.select(MawzoonCatalog.steamedBasmati);
      expect(selection.nextSegment, PlateSegment.vitalFiber);

      selection = selection.select(MawzoonCatalog.charredGardenVeggies);
      expect(selection.nextSegment, isNull);
    });

    test('toggling the scale keeps every component', () {
      final PlateSelection standard = PlateSelection.empty
          .select(MawzoonCatalog.herbGrilledBreast)
          .select(MawzoonCatalog.steamedBasmati);
      final PlateSelection athletic = standard.toggleScale();

      expect(athletic.scale, PortionScale.athleticLoad);
      expect(athletic.protein, standard.protein);
      expect(athletic.carb, standard.carb);
      expect(athletic.toggleScale().scale, PortionScale.standardBalance);
    });

    test('surcharges accumulate across compartments', () {
      final PlateSelection selection = PlateSelection.empty
          .select(MawzoonCatalog.smokedEntrecote)
          .select(MawzoonCatalog.steamedBasmati)
          .select(MawzoonCatalog.charredGardenVeggies);

      expect(
        selection.surchargeMinorUnits,
        MawzoonCatalog.smokedEntrecote.surchargeMinorUnits,
      );
      expect(selection.surchargeMinorUnits, greaterThan(0));
    });

    test('a plate of unsurcharged components costs no extra', () {
      final PlateSelection selection = PlateSelection.empty
          .select(MawzoonCatalog.herbGrilledBreast)
          .select(MawzoonCatalog.steamedBasmati)
          .select(MawzoonCatalog.charredGardenVeggies);

      expect(selection.surchargeMinorUnits, 0);
    });

    test('is a value type', () {
      final PlateSelection a =
          PlateSelection.empty.select(MawzoonCatalog.herbGrilledBreast);
      final PlateSelection b =
          PlateSelection.empty.select(MawzoonCatalog.herbGrilledBreast);

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
        PlateSelection.empty.select(MawzoonCatalog.herbGrilledBreast),
      );
      expect(one, isA<PlateConfiguring>());
      expect(one.canCheckout, isFalse);
      expect(one.remainingSegmentCount, 2);

      final PlateBuilderState two = PlateBuilderState.from(
        PlateSelection.empty
            .select(MawzoonCatalog.herbGrilledBreast)
            .select(MawzoonCatalog.steamedBasmati),
      );
      expect(two, isA<PlateConfiguring>());
      expect(two.remainingSegmentCount, 1);
    });

    test('all three compartments at the house portion derive PlateBalanced',
        () {
      final PlateBuilderState state = PlateBuilderState.from(
        PlateSelection.empty
            .select(MawzoonCatalog.herbGrilledBreast)
            .select(MawzoonCatalog.steamedBasmati)
            .select(MawzoonCatalog.charredGardenVeggies),
      );

      expect(state, isA<PlateBalanced>());
      expect(state.canCheckout, isTrue);
      expect(state.isComplete, isTrue);
      expect(state.remainingSegmentCount, 0);

      final PlateBalanced balanced = state as PlateBalanced;
      expect(balanced.protein, MawzoonCatalog.herbGrilledBreast);
      expect(balanced.finalMacros.isComplete, isTrue);
      expect(balanced.scale, PortionScale.standardBalance);
    });

    test('all three at the athletic load derive PlateVolumeAdjusted', () {
      final PlateBuilderState state = PlateBuilderState.from(
        PlateSelection.empty
            .select(MawzoonCatalog.herbGrilledBreast)
            .select(MawzoonCatalog.steamedBasmati)
            .select(MawzoonCatalog.charredGardenVeggies)
            .toggleScale(),
      );

      expect(state, isA<PlateVolumeAdjusted>());
      expect(state, isNot(isA<PlateBalanced>()));
      expect(state.canCheckout, isTrue);
      expect(state.isComplete, isTrue);
      expect(state.scale, PortionScale.athleticLoad);
    });

    test('round-trips back to the selection it came from', () {
      final PlateSelection original = PlateSelection.empty
          .select(MawzoonCatalog.koftaSpicedMince)
          .select(MawzoonCatalog.wholeWheatPasta)
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
          athleticEmpty.select(MawzoonCatalog.herbGrilledBreast),
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
          protein: MawzoonCatalog.herbGrilledBreast,
          carb: MawzoonCatalog.steamedBasmati,
          fiber: MawzoonCatalog.charredGardenVeggies,
          currentMacros:
              NutritionalSummary.empty(PortionScale.standardBalance),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('PlateVolumeAdjusted', () {
    PlateVolumeAdjusted adjusted() => PlateBuilderState.from(
          PlateSelection.empty
              .select(MawzoonCatalog.smokedEntrecote)
              .select(MawzoonCatalog.wholeBulgur)
              .select(MawzoonCatalog.mediterraneanSumacSalad)
              .copyWith(scale: PortionScale.athleticLoad),
        ) as PlateVolumeAdjusted;

    test('carries both readings so the delta comes from the engine', () {
      final PlateVolumeAdjusted state = adjusted();

      expect(state.adjustedMacros.scale, PortionScale.athleticLoad);
      expect(state.baselineMacros.scale, PortionScale.standardBalance);
      expect(state.macros, state.adjustedMacros);
    });

    test('the baseline is the same three components, not a different plate',
        () {
      final PlateVolumeAdjusted state = adjusted();
      expect(
        state.baselineMacros.filledSegments,
        state.adjustedMacros.filledSegments,
      );
      expect(
        state.baselineMacros.totalPortionGrams,
        lessThan(state.adjustedMacros.totalPortionGrams),
      );
    });

    test('reports what the adjustment actually cost', () {
      final PlateVolumeAdjusted state = adjusted();

      expect(state.kilocalorieDelta, greaterThan(0));
      expect(state.proteinGramsDelta, greaterThan(0));
      expect(state.portionGramsDelta, greaterThan(0));
      expect(
        state.kilocalorieDelta,
        closeTo(
          state.adjustedMacros.totalKilocalories -
              state.baselineMacros.totalKilocalories,
          1e-9,
        ),
      );
    });

    test('reads against the athletic band, not the standard one', () {
      final PlateVolumeAdjusted state = adjusted();
      expect(state.adjustedMacros.band.nominalKilocalories, 780);
      expect(state.baselineMacros.band.nominalKilocalories, 550);
    });

    test('round-trips back to its selection', () {
      final PlateVolumeAdjusted state = adjusted();
      expect(state.selection.scale, PortionScale.athleticLoad);
      expect(state.selection.protein, MawzoonCatalog.smokedEntrecote);
      expect(PlateBuilderState.from(state.selection), state);
    });

    test('toggling back down returns to PlateBalanced', () {
      final PlateBuilderState back =
          PlateBuilderState.from(adjusted().selection.toggleScale());
      expect(back, isA<PlateBalanced>());
      expect(back.scale, PortionScale.standardBalance);
    });
  });

  // The whole point of a sealed hierarchy: the compiler, not a code reviewer,
  // is what guarantees a screen handled every case.
  group('exhaustiveness', () {
    String describe(PlateBuilderState state) => switch (state) {
          PlateEmpty() => 'empty',
          PlateConfiguring() => 'configuring',
          PlateBalanced() => 'balanced',
          PlateVolumeAdjusted() => 'adjusted',
        };

    test('a switch with no default covers all four states', () {
      final PlateSelection full = PlateSelection.empty
          .select(MawzoonCatalog.herbGrilledBreast)
          .select(MawzoonCatalog.steamedBasmati)
          .select(MawzoonCatalog.charredGardenVeggies);

      expect(describe(PlateBuilderState.from(PlateSelection.empty)), 'empty');
      expect(
        describe(PlateBuilderState.from(
          PlateSelection.empty.select(MawzoonCatalog.herbGrilledBreast),
        ),),
        'configuring',
      );
      expect(describe(PlateBuilderState.from(full)), 'balanced');
      expect(describe(PlateBuilderState.from(full.toggleScale())), 'adjusted');
    });

    test('the four states partition every reachable selection', () {
      final Set<String> seen = <String>{};
      for (final PortionScale scale in PortionScale.values) {
        PlateSelection selection = PlateSelection(scale: scale);
        seen.add(describe(PlateBuilderState.from(selection)));
        selection = selection.select(MawzoonCatalog.koftaSpicedMince);
        seen.add(describe(PlateBuilderState.from(selection)));
        selection = selection.select(MawzoonCatalog.toastedQuinoa);
        seen.add(describe(PlateBuilderState.from(selection)));
        selection = selection.select(MawzoonCatalog.charredGardenVeggies);
        seen.add(describe(PlateBuilderState.from(selection)));
      }
      expect(seen, <String>{'empty', 'configuring', 'balanced', 'adjusted'});
    });

    test('only the two complete states allow checkout', () {
      final PlateSelection full = PlateSelection.empty
          .select(MawzoonCatalog.marinatedThighs)
          .select(MawzoonCatalog.wholeWheatPasta)
          .select(MawzoonCatalog.mediterraneanSumacSalad);

      expect(PlateBuilderState.from(PlateSelection.empty).canCheckout, isFalse);
      expect(
        PlateBuilderState.from(
          PlateSelection.empty.select(MawzoonCatalog.marinatedThighs),
        ).canCheckout,
        isFalse,
      );
      expect(PlateBuilderState.from(full).canCheckout, isTrue);
      expect(PlateBuilderState.from(full.toggleScale()).canCheckout, isTrue);
    });
  });
}
