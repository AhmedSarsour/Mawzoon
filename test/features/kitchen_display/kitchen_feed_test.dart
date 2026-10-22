import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/kitchen_display/application/kitchen_board_controller.dart';
import 'package:mawzoon/features/kitchen_display/application/kitchen_order_feed.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_station.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_ticket.dart';
import 'package:mawzoon/services/kitchen_wire.dart';

Map<String, dynamic> _row(
  int number, {
  String status = 'PENDING',
  Map<String, bool> stations = const <String, bool>{},
  String proteinId = 'protein.herb_grilled_breast',
  String volume = 'STANDARD',
  String type = 'PICKUP',
  int minutesAgo = 5,
}) =>
    <String, dynamic>{
      'id': 'order-$number',
      'order_number': number,
      'order_type': type,
      'status': status,
      'note': null,
      'created_at': DateTime.now()
          .toUtc()
          .subtract(Duration(minutes: minutesAgo))
          .toIso8601String(),
      'order_items': <dynamic>[
        <String, dynamic>{
          'id': 'item-$number',
          'protein_id': proteinId,
          'carb_id': 'carb.steamed_basmati',
          'fiber_id': 'fiber.charred_garden_veggies',
          'volume_type': volume,
          'station_status': stations,
        },
      ],
    };

final class _FakeFeed implements KitchenOrderFeed {
  final StreamController<List<KitchenTicket>> out =
      StreamController<List<KitchenTicket>>.broadcast(sync: true);
  final List<String> calls = <String>[];
  int refreshes = 0;
  Completer<void>? gate;

  void push(List<Map<String, dynamic>> rows) =>
      out.add(kitchenSnapshotFromRows(rows).tickets);

  @override
  Stream<List<KitchenTicket>> watch() => out.stream;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> setStation(
    String code,
    KitchenStation station, {
    required bool done,
  }) async {
    calls.add('$code ${station.name}=$done');
    await gate?.future;
  }

  @override
  Future<void> markPlated(String code) async => calls.add('$code plated');

  @override
  Future<void> markCollected(String code) async => calls.add('$code collected');

  @override
  void dispose() {}
}

final class _CountingChime implements KitchenChime {
  int rings = 0;
  @override
  void ring() => rings++;
}

void main() {
  group('kitchenSnapshotFromRows', () {
    test('an order becomes a ticket the line can read', () {
      final KitchenSnapshot s = kitchenSnapshotFromRows(<dynamic>[
        _row(
          104,
          status: 'ASSEMBLING',
          stations: <String, bool>{'grill': true, 'prep': false},
          volume: 'ATHLETIC',
          type: 'DELIVERY',
        ),
      ]);
      final KitchenTicket t = s.tickets.single;
      expect(t.code, 'M-104');
      expect(t.scale, PortionScale.athleticLoad);
      expect(t.mode, FulfilmentMode.delivery);
      expect(t.instructions.keys.toSet(), KitchenStation.values.toSet());
      expect(
        t.instructionFor(KitchenStation.grill)!.option,
        MawzoonCatalog.herbGrilledBreast,
      );
      expect(t.status.prepped, <KitchenStation>{KitchenStation.grill});
      expect(s.refs['M-104']!.itemId, 'item-104');
    });

    test('READY is in the packaging queue; oldest first on the line', () {
      final KitchenSnapshot s = kitchenSnapshotFromRows(<dynamic>[
        _row(2, minutesAgo: 1),
        _row(1, minutesAgo: 9),
        _row(
          3,
          status: 'READY',
          stations: <String, bool>{
            'grill': true,
            'starch': true,
            'prep': true,
          },
        ),
      ]);
      expect(
        s.tickets.map((KitchenTicket t) => t.code),
        <String>['M-1', 'M-3', 'M-2'],
      );
      expect(s.tickets[1].status.isArchived, isTrue);
    });

    test('a plate this build cannot read is left off, not half-shown', () {
      final KitchenSnapshot s = kitchenSnapshotFromRows(<dynamic>[
        _row(7, proteinId: 'protein.from_a_newer_menu'),
        _row(8),
      ]);
      expect(s.tickets.map((KitchenTicket t) => t.code), <String>['M-8']);
    });
  });

  group('board on a feed', () {
    late _FakeFeed feed;
    late _CountingChime chime;
    late KitchenBoardController board;

    setUp(() {
      feed = _FakeFeed();
      chime = _CountingChime();
      board = KitchenBoardController(feed: feed, chime: chime);
    });
    tearDown(() => board.dispose());

    test('snapshots fill the line and the packaging queue', () {
      feed.push(<Map<String, dynamic>>[
        _row(1),
        _row(
          2,
          status: 'READY',
          stations: <String, bool>{
            'grill': true,
            'starch': true,
            'prep': true,
          },
        ),
      ]);
      expect(board.line.map((KitchenTicket t) => t.code), <String>['M-1']);
      expect(board.packaging.map((KitchenTicket t) => t.code), <String>['M-2']);
    });

    test(
        'a tap sets the station, and tapping again sets it back — never a flip',
        () async {
      feed.push(<Map<String, dynamic>>[_row(1)]);
      board.toggleStation('M-1', KitchenStation.grill);
      await pumpEventQueue();
      board.toggleStation('M-1', KitchenStation.grill);
      await pumpEventQueue();
      expect(feed.calls, <String>['M-1 grill=true', 'M-1 grill=false']);
    });

    test('the third station plates it: written, chimed, packed', () async {
      feed.push(<Map<String, dynamic>>[
        _row(
          1,
          status: 'ASSEMBLING',
          stations: <String, bool>{'grill': true, 'starch': true},
        ),
      ]);
      board.toggleStation('M-1', KitchenStation.prep);
      await pumpEventQueue();
      expect(feed.calls, <String>['M-1 prep=true', 'M-1 plated']);
      expect(chime.rings, 1);
      expect(board.packaging.single.code, 'M-1');

      board.clearPackaged('M-1');
      await pumpEventQueue();
      expect(feed.calls.last, 'M-1 collected');
    });

    test('a snapshot read mid-write does not undo the tap; one refresh follows',
        () async {
      feed.push(<Map<String, dynamic>>[_row(1)]);
      feed.gate = Completer<void>();
      board.toggleStation('M-1', KitchenStation.grill);
      feed.push(<Map<String, dynamic>>[_row(1)]); // stale: grill not yet saved
      expect(board.line.single.isPrepped(KitchenStation.grill), isTrue);

      feed.gate!.complete();
      await pumpEventQueue();
      expect(feed.refreshes, 1);
    });

    test(
        'a plate saved with every station but never marked plated is finished, once',
        () async {
      final Map<String, bool> all = <String, bool>{
        'grill': true,
        'starch': true,
        'prep': true,
      };
      feed.push(
        <Map<String, dynamic>>[_row(1, status: 'ASSEMBLING', stations: all)],
      );
      await pumpEventQueue();
      feed.push(
        <Map<String, dynamic>>[_row(1, status: 'ASSEMBLING', stations: all)],
      );
      await pumpEventQueue();
      expect(feed.calls, <String>['M-1 plated']);
    });
  });
}
