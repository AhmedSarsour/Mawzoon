import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/measure/quantity.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/recipe_calibration.dart';
import 'package:mawzoon/features/manager_suite/application/back_office_store.dart';
import 'package:mawzoon/features/manager_suite/application/manager_suite_controller.dart';
import 'package:mawzoon/features/manager_suite/domain/inventory_ledger.dart';
import 'package:mawzoon/features/manager_suite/domain/raw_ingredient.dart';

final class _FakeStore implements BackOfficeStore {
  _FakeStore(this.snapshot);

  BackOfficeSnapshot snapshot;
  final StreamController<void> pings =
      StreamController<void>.broadcast(sync: true);
  final List<String> calls = <String>[];
  int loads = 0;
  Completer<void>? gate;
  bool failWrites = false;

  Future<void> _write(String call) async {
    calls.add(call);
    await gate?.future;
    if (failWrites) throw StateError('offline');
  }

  @override
  Future<BackOfficeSnapshot> load() async {
    loads++;
    return snapshot;
  }

  @override
  Stream<void> changes() => pings.stream;

  @override
  Future<void> setCount(String id, int minor) => _write('count $id $minor');

  @override
  Future<void> adjust(String id, int delta) => _write('adjust $id $delta');

  @override
  Future<void> setForcedOff(String id, {required bool off}) =>
      _write('off $id $off');

  @override
  Future<void> setPortionFactor(String id, double f) => _write('factor $id $f');

  @override
  void dispose() {}
}

BackOfficeSnapshot _snap({
  int oilMl = 2000,
  Set<String> off = const <String>{},
}) =>
    BackOfficeSnapshot(
      stockMinorUnits: <String, int>{
        RawStore.oliveOil.id: oilMl * 1000,
        'ingredient.dropped_from_menu': 5,
      },
      forcedOff: off,
      rails: const StockRails(safetyBuffer: 3, lowWaterMark: 9),
    );

void main() {
  late _FakeStore store;
  late ManagerSuiteController suite;

  Future<void> start(BackOfficeSnapshot s) async {
    store = _FakeStore(s);
    suite = ManagerSuiteController(store: store);
    await pumpEventQueue();
  }

  tearDown(() => suite.dispose());

  test('loads the server\'s counts, switches and rails', () async {
    await start(_snap(off: <String>{MawzoonCatalog.airFriedSpicedPotatoes.id}));

    expect(suite.ledger.onHand(RawStore.oliveOil), Quantity.millilitres(2000));
    expect(suite.ledger.rails.safetyBuffer, 3);
    expect(
      suite.availability.canOrder(MawzoonCatalog.airFriedSpicedPotatoes.id),
      isFalse,
    );
  });

  test('every manager action is written as a fact the server can apply',
      () async {
    await start(_snap());
    suite.setCount(RawStore.oliveOil, Quantity.millilitres(1500));
    suite.receive(RawStore.oliveOil, Quantity.millilitres(500));
    suite.writeOff(RawStore.oliveOil, Quantity.millilitres(20));
    suite.setForcedOff(MawzoonCatalog.spaghetti.id, off: true);
    suite.calibrate(
      CalibrationDraft.from(MawzoonCatalog.herbGrilledBreast).copyWith(
        portionGrams: MawzoonCatalog.herbGrilledBreast.basePortionGrams * 1.1,
      ),
      published: MawzoonCatalog.herbGrilledBreast,
    );
    await pumpEventQueue();

    final String oil = RawStore.oliveOil.id;
    expect(store.calls.take(4), <String>[
      'count $oil 1500000',
      'adjust $oil 500000',
      'adjust $oil -20000',
      'off ${MawzoonCatalog.spaghetti.id} true',
    ]);
    expect(
      store.calls.last,
      startsWith('factor ${MawzoonCatalog.herbGrilledBreast.id} 1.1'),
    );
  });

  test('an order drawing stock elsewhere shows up here', () async {
    await start(_snap());
    store.snapshot = _snap(oilMl: 1200);
    store.pings.add(null);
    await pumpEventQueue();
    expect(suite.ledger.onHand(RawStore.oliveOil), Quantity.millilitres(1200));
  });

  test('a reload never lands on top of a write still in flight', () async {
    await start(_snap());
    final int loadsBefore = store.loads;
    store.gate = Completer<void>();
    suite.setCount(RawStore.oliveOil, Quantity.millilitres(900));
    store.pings.add(null); // the server echoes before our write returns
    await pumpEventQueue();
    expect(store.loads, loadsBefore, reason: 'held until the write lands');
    expect(suite.ledger.onHand(RawStore.oliveOil), Quantity.millilitres(900));

    store.snapshot = _snap(oilMl: 900);
    store.gate!.complete();
    await pumpEventQueue();
    expect(store.loads, loadsBefore + 1);
  });

  test(
      'a failed write is undone by the server\'s truth, not left looking saved',
      () async {
    await start(_snap());
    store.failWrites = true;
    suite.setForcedOff(MawzoonCatalog.spaghetti.id, off: true);
    expect(suite.ledger.forcedOff, contains(MawzoonCatalog.spaghetti.id));
    await pumpEventQueue();
    expect(
      suite.ledger.forcedOff,
      isNot(contains(MawzoonCatalog.spaghetti.id)),
    );
  });
}
