import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/plate_builder/application/plate_builder_controller.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_builder_event.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_builder_state.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';

/// Collects everything a controller emits so a test can assert on the exact
/// sequence, which is what the haptic layer actually consumes.
class _EventRecorder {
  _EventRecorder(PlateBuilderController controller) {
    _subscription = controller.events.listen(events.add);
  }

  final List<PlateBuilderEvent> events = <PlateBuilderEvent>[];
  late final StreamSubscription<PlateBuilderEvent> _subscription;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  late PlateBuilderController controller;
  late _EventRecorder recorder;

  setUp(() {
    controller = PlateBuilderController();
    recorder = _EventRecorder(controller);
  });

  tearDown(() async {
    await recorder.cancel();
    controller.dispose();
  });

  group('lifecycle', () {
    test('starts empty at the standard portion', () {
      expect(controller.value, isA<PlateEmpty>());
      expect(controller.scale, PortionScale.standardBalance);
      expect(controller.canCheckout, isFalse);
      expect(controller.macros.totalKilocalories, 0);
    });

    test('can be seeded with an existing selection', () {
      final PlateBuilderController seeded = PlateBuilderController(
        initialSelection: PlateSelection.empty
            .select(MawzoonCatalog.smashedLeanBeef)
            .select(MawzoonCatalog.steamedBasmati)
            .select(MawzoonCatalog.charredGardenVeggies),
      );
      addTearDown(seeded.dispose);

      expect(seeded.value, isA<PlateBalanced>());
      expect(seeded.canCheckout, isTrue);
    });
  });

  group('transitions', () {
    test('walks empty -> configuring -> balanced', () {
      final List<Type> observed = <Type>[];
      controller.addListener(() => observed.add(controller.value.runtimeType));

      controller.select(MawzoonCatalog.herbGrilledBreast);
      controller.select(MawzoonCatalog.airFriedSpicedPotatoes);
      controller.select(MawzoonCatalog.charredGardenVeggies);

      expect(observed, <Type>[PlateConfiguring, PlateConfiguring, PlateBalanced]);
      expect(controller.canCheckout, isTrue);
    });

    test('order of assembly does not matter', () {
      controller
        ..select(MawzoonCatalog.charredGardenVeggies)
        ..select(MawzoonCatalog.toastedQuinoa)
        ..select(MawzoonCatalog.marinatedThighs);

      expect(controller.value, isA<PlateBalanced>());
    });

    test('clearing a compartment releases the lock', () {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies);
      expect(controller.value, isA<PlateBalanced>());

      controller.clearSegment(PlateSegment.smartCarb);
      expect(controller.value, isA<PlateConfiguring>());
      expect(controller.canCheckout, isFalse);
    });

    test('reset returns to empty but keeps the guest\'s scale preference', () {
      controller
        ..setScale(PortionScale.athleticLoad)
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..reset();

      expect(controller.value, isA<PlateEmpty>());
      expect(controller.scale, PortionScale.athleticLoad);
    });

    test('changing scale on a finished plate moves it to PlateVolumeAdjusted',
        () {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.airFriedSpicedPotatoes)
        ..select(MawzoonCatalog.charredGardenVeggies);

      expect(controller.value, isA<PlateBalanced>());
      final double standard = controller.macros.totalKilocalories;

      controller.toggleScale();

      expect(controller.value, isA<PlateVolumeAdjusted>());
      expect(controller.macros.totalKilocalories, greaterThan(standard));
      expect(controller.macros.scale, PortionScale.athleticLoad);
      expect(controller.canCheckout, isTrue,
          reason: 'a loaded plate is still an orderable plate',);

      final PlateVolumeAdjusted adjusted =
          controller.value as PlateVolumeAdjusted;
      expect(adjusted.kilocalorieDelta,
          closeTo(controller.macros.totalKilocalories - standard, 1e-9),);
    });

    test('toggling back down returns to PlateBalanced', () {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.airFriedSpicedPotatoes)
        ..select(MawzoonCatalog.charredGardenVeggies)
        ..toggleScale()
        ..toggleScale();

      expect(controller.value, isA<PlateBalanced>());
      expect(controller.scale, PortionScale.standardBalance);
    });

    test('a partial plate on the athletic load stays PlateConfiguring', () {
      controller
        ..setScale(PortionScale.athleticLoad)
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.airFriedSpicedPotatoes);

      expect(controller.value, isA<PlateConfiguring>());
      expect(controller.scale, PortionScale.athleticLoad);
    });

    test('completing a plate already on the athletic load lands adjusted', () {
      controller
        ..setScale(PortionScale.athleticLoad)
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.airFriedSpicedPotatoes)
        ..select(MawzoonCatalog.charredGardenVeggies);

      expect(controller.value, isA<PlateVolumeAdjusted>());
    });
  });

  group('no-op guards', () {
    test('re-selecting the same component changes nothing and emits nothing',
        () async {
      controller.select(MawzoonCatalog.herbGrilledBreast);
      final PlateBuilderState before = controller.value;

      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.select(MawzoonCatalog.herbGrilledBreast);
      await recorder.settle();

      expect(identical(controller.value, before), isTrue);
      expect(notifications, 0);
      expect(recorder.events.whereType<SegmentFilled>(), hasLength(1));
    });

    test('clearing an already-empty compartment is inert', () async {
      controller.clearSegment(PlateSegment.vitalFiber);
      await recorder.settle();

      expect(controller.value, isA<PlateEmpty>());
      expect(recorder.events, isEmpty);
    });

    test('setting the scale already in force is inert', () async {
      controller.setScale(PortionScale.standardBalance);
      await recorder.settle();

      expect(recorder.events, isEmpty);
    });

    test('resetting an empty plate is inert', () async {
      controller.reset();
      await recorder.settle();

      expect(recorder.events, isEmpty);
    });
  });

  group('events and haptics', () {
    test('a fill reports what it displaced', () async {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.smashedLeanBeef);
      await recorder.settle();

      final List<SegmentFilled> fills =
          recorder.events.whereType<SegmentFilled>().toList();
      expect(fills, hasLength(2));
      expect(fills.first.replaced, isNull);
      expect(fills.last.replaced, MawzoonCatalog.herbGrilledBreast);
      expect(fills.last.segment, PlateSegment.protein);
      expect(fills.last.haptic, HapticCue.light);
    });

    test('the balance lock fires exactly once, on the threshold', () async {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies);
      await recorder.settle();

      final List<BalanceLocked> locks =
          recorder.events.whereType<BalanceLocked>().toList();
      expect(locks, hasLength(1));
      expect(locks.single.haptic, HapticCue.medium);
      expect(locks.single.summary.isComplete, isTrue);
    });

    test('swapping on an already-balanced plate does not re-fire the lock',
        () async {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies)
        ..select(MawzoonCatalog.smashedLeanBeef)
        ..select(MawzoonCatalog.wholeBulgur);
      await recorder.settle();

      expect(recorder.events.whereType<BalanceLocked>(), hasLength(1));
    });

    test('breaking and remaking the plate fires the lock again', () async {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies)
        ..clearSegment(MawzoonCatalog.steamedBasmati.segment)
        ..select(MawzoonCatalog.wholeBulgur);
      await recorder.settle();

      expect(recorder.events.whereType<BalanceLocked>(), hasLength(2));
      expect(recorder.events.whereType<BalanceReleased>(), hasLength(1));
    });


    test('a volume change on a finished plate does not re-fire the lock',
        () async {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies)
        ..toggleScale()
        ..toggleScale();
      await recorder.settle();

      // Balanced -> VolumeAdjusted -> Balanced changes the state class twice
      // without the plate ever becoming incomplete, so the milestone is spent
      // exactly once.
      expect(recorder.events.whereType<BalanceLocked>(), hasLength(1));
      expect(recorder.events.whereType<BalanceReleased>(), isEmpty);
      expect(recorder.events.whereType<ScaleChanged>(), hasLength(2));
    });

    test('completing a plate on the athletic load still fires the lock',
        () async {
      controller
        ..setScale(PortionScale.athleticLoad)
        ..select(MawzoonCatalog.koftaSpicedMince)
        ..select(MawzoonCatalog.wholeWheatPasta)
        ..select(MawzoonCatalog.mediterraneanSumacSalad);
      await recorder.settle();

      final BalanceLocked lock =
          recorder.events.whereType<BalanceLocked>().single;
      expect(lock.summary.scale, PortionScale.athleticLoad);
      expect(lock.summary.isComplete, isTrue);
    });

    test('undoing is silent — no haptic punishes a change of mind', () async {
      controller
        ..select(MawzoonCatalog.herbGrilledBreast)
        ..select(MawzoonCatalog.steamedBasmati)
        ..select(MawzoonCatalog.charredGardenVeggies)
        ..clearSegment(PlateSegment.vitalFiber);
      await recorder.settle();

      final BalanceReleased release =
          recorder.events.whereType<BalanceReleased>().single;
      expect(release.haptic, HapticCue.none);
    });

    test('replaceSelection can complete a plate and fire the lock', () async {
      controller.replaceSelection(
        PlateSelection.empty
            .select(MawzoonCatalog.pulledSlowCookedBeef)
            .select(MawzoonCatalog.sweetPotatoWedges)
            .select(MawzoonCatalog.mediterraneanSumacSalad),
      );
      await recorder.settle();

      expect(controller.value, isA<PlateBalanced>());
      expect(recorder.events.whereType<BalanceLocked>(), hasLength(1));
    });
  });

  group('disposal', () {
    test('closes the event stream so listeners tear down cleanly', () async {
      final PlateBuilderController disposable = PlateBuilderController();
      final List<PlateBuilderEvent> seen = <PlateBuilderEvent>[];
      bool closed = false;
      final StreamSubscription<PlateBuilderEvent> subscription =
          disposable.events.listen(seen.add, onDone: () => closed = true);

      disposable.select(MawzoonCatalog.herbGrilledBreast);
      disposable.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect(closed, isTrue);
      await subscription.cancel();
    });
  });
}
