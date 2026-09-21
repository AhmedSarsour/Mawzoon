import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/dietary_metadata.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/menu/plate_segment.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/kitchen_display/application/kitchen_board_controller.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_station.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_ticket.dart';
import 'package:mawzoon/features/kitchen_display/presentation/kitchen_board_screen.dart';
import 'package:mawzoon/features/kitchen_display/presentation/kitchen_ticket_card.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/main_kitchen.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// A chime that counts, so "rings exactly once" is a claim and not a hope.
final class RecordingChime implements KitchenChime {
  int rings = 0;

  @override
  void ring() => rings++;
}

/// Owns the board for the duration of a widget test.
///
/// [KitchenBoardScreen] deliberately does not dispose a controller it was
/// handed — an externally owned board outlives the screen. So something in the
/// tree has to, and a tearDown cannot: it runs *after* the test framework
/// checks for pending timers, and the board's clock is one. This is also the
/// correct production shape for a board that outlives a single route.
class _BoardHost extends StatefulWidget {
  const _BoardHost({required this.board, required this.child, super.key});

  final KitchenBoardController board;
  final Widget child;

  @override
  State<_BoardHost> createState() => _BoardHostState();
}

class _BoardHostState extends State<_BoardHost> {
  @override
  void dispose() {
    widget.board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  final DateTime placed = DateTime.utc(2026, 3, 14, 19, 30);

  PlateSelection completePlate({
    PortionScale scale = PortionScale.standardBalance,
  }) =>
      PlateSelection(
        protein: MawzoonCatalog.smokedEntrecote,
        carb: MawzoonCatalog.wholeBulgur,
        fiber: MawzoonCatalog.mediterraneanSumacSalad,
        scale: scale,
      );

  OrderDraft draft({
    PortionScale scale = PortionScale.standardBalance,
    FulfilmentMode mode = FulfilmentMode.delivery,
    String? note,
  }) =>
      OrderDraft(
        selection: completePlate(scale: scale),
        mode: mode,
        payment: PaymentMethod.wallet,
        address: mode == FulfilmentMode.delivery
            ? const DeliveryAddress(
                id: 'addr.test',
                label: LocalizedText(ar: 'البيت', en: 'Home'),
                line: '12 Olive St',
                district: 'Al Olaya',
              )
            : null,
        note: note,
      );

  KitchenTicket ticket({
    String code = 'M-101',
    DateTime? at,
    PortionScale scale = PortionScale.standardBalance,
    String? note,
  }) =>
      KitchenTicket.fromOrder(
        draft(scale: scale, note: note),
        code: code,
        placedAt: at ?? placed,
      );

  // -------------------------------------------------------------------
  // Stations
  // -------------------------------------------------------------------

  group('stations', () {
    test('every compartment has exactly one station, and vice versa', () {
      final Set<PlateSegment> covered =
          KitchenStation.values.map((KitchenStation s) => s.segment).toSet();
      expect(covered, PlateSegment.values.toSet());
      expect(covered.length, KitchenStation.values.length);
    });

    test('forSegment is total and round-trips', () {
      for (final PlateSegment segment in PlateSegment.values) {
        expect(KitchenStation.forSegment(segment).segment, segment);
      }
    });

    test('the line runs grill, starch, prep', () {
      expect(KitchenStation.line, <KitchenStation>[
        KitchenStation.grill,
        KitchenStation.starch,
        KitchenStation.prep,
      ]);
      expect(KitchenStation.line.toSet(), KitchenStation.values.toSet());
    });

    test('every station is named in both languages', () {
      for (final KitchenStation station in KitchenStation.values) {
        expect(station.label.ar, isNotEmpty);
        expect(station.label.en, isNotEmpty);
      }
    });
  });

  // -------------------------------------------------------------------
  // Station instructions
  // -------------------------------------------------------------------

  group('station instructions', () {
    test('are derived from the catalogue, not restated', () {
      final StationInstruction grill = StationInstruction.from(
        MawzoonCatalog.smokedEntrecote,
        PortionScale.standardBalance,
      );
      expect(grill.station, KitchenStation.grill);
      expect(grill.option, same(MawzoonCatalog.smokedEntrecote));
      expect(grill.method, MawzoonCatalog.smokedEntrecote.method);
      expect(grill.note, MawzoonCatalog.smokedEntrecote.kitchenNote);
      expect(
        grill.targetGrams,
        MawzoonCatalog.smokedEntrecote
            .atScale(PortionScale.standardBalance)
            .portionGrams,
      );
    });

    test('the target weight follows the volume toggle', () {
      final StationInstruction standard = StationInstruction.from(
        MawzoonCatalog.smokedEntrecote,
        PortionScale.standardBalance,
      );
      final StationInstruction athletic = StationInstruction.from(
        MawzoonCatalog.smokedEntrecote,
        PortionScale.athleticLoad,
      );
      expect(athletic.targetGrams, greaterThan(standard.targetGrams));
      expect(
        athletic.targetGrams,
        MawzoonCatalog.smokedEntrecote
            .atScale(PortionScale.athleticLoad)
            .portionGrams,
      );
    });

    test('doneness is a grill concern only', () {
      final StationInstruction grill = StationInstruction.from(
        MawzoonCatalog.smokedEntrecote,
        PortionScale.standardBalance,
      );
      expect(grill.doneness, MawzoonCatalog.smokedEntrecote.doneness);
      expect(grill.hasDoneness, isTrue);

      for (final IngredientOption option in <IngredientOption>[
        MawzoonCatalog.wholeBulgur,
        MawzoonCatalog.mediterraneanSumacSalad,
      ]) {
        final StationInstruction other = StationInstruction.from(
          option,
          PortionScale.standardBalance,
        );
        expect(other.doneness, Doneness.notApplicable);
        expect(other.hasDoneness, isFalse);
      }
    });

    test('every catalogue component can be routed to a station', () {
      for (final IngredientOption option in MawzoonCatalog.all) {
        final StationInstruction instruction = StationInstruction.from(
          option,
          PortionScale.standardBalance,
        );
        expect(instruction.station.segment, option.segment);
        expect(instruction.displayGrams, greaterThan(0));
        expect(
          instruction.note,
          isNotNull,
          reason: '${option.id} reaches the line without an instruction',
        );
      }
    });

    test('the weight the line reads is the cooked weight, rounded', () {
      final StationInstruction instruction = StationInstruction.from(
        MawzoonCatalog.mediterraneanSumacSalad,
        PortionScale.athleticLoad,
      );
      expect(instruction.displayGrams, instruction.targetGrams.round());
    });
  });

  // -------------------------------------------------------------------
  // Urgency
  // -------------------------------------------------------------------

  group('urgency', () {
    test('a fresh ticket is on pace', () {
      expect(TicketUrgency.forAge(Duration.zero), TicketUrgency.onPace);
    });

    test('eight minutes is the first boundary, and it is exclusive', () {
      expect(
        TicketUrgency.forAge(const Duration(minutes: 7, seconds: 59)),
        TicketUrgency.onPace,
      );
      expect(
        TicketUrgency.forAge(const Duration(minutes: 8)),
        TicketUrgency.tightening,
      );
    });

    test('fifteen minutes is the second boundary, and it is exclusive', () {
      expect(
        TicketUrgency.forAge(const Duration(minutes: 14, seconds: 59)),
        TicketUrgency.tightening,
      );
      expect(
        TicketUrgency.forAge(const Duration(minutes: 15)),
        TicketUrgency.overdue,
      );
    });

    test('overdue has no ceiling that can be fallen out of', () {
      expect(
        TicketUrgency.forAge(const Duration(days: 400)),
        TicketUrgency.overdue,
      );
    });

    test('the bands are ordered, and only three', () {
      expect(TicketUrgency.values, hasLength(3));
      expect(
        TicketUrgency.onPace.ceiling,
        lessThan(TicketUrgency.tightening.ceiling),
      );
      expect(
        TicketUrgency.tightening.ceiling,
        lessThan(TicketUrgency.overdue.ceiling),
      );
    });

    test('a ticket reports its own band against a given clock', () {
      final KitchenTicket t = ticket();
      expect(t.urgencyAt(placed), TicketUrgency.onPace);
      expect(
        t.urgencyAt(placed.add(const Duration(minutes: 9))),
        TicketUrgency.tightening,
      );
      expect(
        t.urgencyAt(placed.add(const Duration(minutes: 22))),
        TicketUrgency.overdue,
      );
      expect(
        t.ageAt(placed.add(const Duration(minutes: 3))),
        const Duration(minutes: 3),
      );
    });

    test('every band reads in both languages', () {
      for (final TicketUrgency band in TicketUrgency.values) {
        expect(band.label.ar, isNotEmpty);
        expect(band.label.en, isNotEmpty);
      }
    });
  });

  // -------------------------------------------------------------------
  // The sealed status
  // -------------------------------------------------------------------

  group('ticket status', () {
    test('nothing prepped is waiting', () {
      final TicketStatus status = TicketStatus.from(
        prepped: const <KitchenStation>{},
        packaged: false,
      );
      expect(status, isA<TicketWaiting>());
      expect(status.prepped, isEmpty);
      expect(status.isPlated, isFalse);
      expect(status.isArchived, isFalse);
    });

    test('one or two prepped is assembling, and knows what is left', () {
      final TicketStatus one = TicketStatus.from(
        prepped: <KitchenStation>{KitchenStation.grill},
        packaged: false,
      );
      expect(one, isA<TicketAssembling>());
      expect(
        (one as TicketAssembling).remaining,
        <KitchenStation>{KitchenStation.starch, KitchenStation.prep},
      );

      final TicketStatus two = TicketStatus.from(
        prepped: <KitchenStation>{KitchenStation.grill, KitchenStation.prep},
        packaged: false,
      );
      expect(two, isA<TicketAssembling>());
      expect(
        (two as TicketAssembling).remaining,
        <KitchenStation>{KitchenStation.starch},
      );
      expect(two.isPlated, isFalse);
    });

    test('all three prepped is plated', () {
      final TicketStatus status = TicketStatus.from(
        prepped: KitchenStation.values.toSet(),
        packaged: false,
      );
      expect(status, isA<TicketPlated>());
      expect(status.isPlated, isTrue);
      expect(status.isArchived, isFalse);
    });

    test('packaged wins over everything else', () {
      expect(
        TicketStatus.from(
          prepped: const <KitchenStation>{},
          packaged: true,
        ),
        isA<TicketPackaging>(),
      );
      final TicketStatus archived = TicketStatus.from(
        prepped: KitchenStation.values.toSet(),
        packaged: true,
      );
      expect(archived, isA<TicketPackaging>());
      expect(archived.isArchived, isTrue);
      expect(archived.isPlated, isTrue);
    });

    test('the four states are exhaustive over a switch', () {
      String describe(TicketStatus status) => switch (status) {
            TicketWaiting() => 'waiting',
            TicketAssembling(prepped: final Set<KitchenStation> done) =>
              'assembling ${done.length}',
            TicketPlated() => 'plated',
            TicketPackaging() => 'packaging',
          };

      expect(describe(const TicketWaiting()), 'waiting');
      expect(
        describe(
          TicketAssembling(prepped: <KitchenStation>{KitchenStation.grill}),
        ),
        'assembling 1',
      );
      expect(describe(const TicketPlated()), 'plated');
      expect(describe(const TicketPackaging()), 'packaging');
    });

    test('assembling compares by content, not identity', () {
      expect(
        TicketAssembling(prepped: <KitchenStation>{KitchenStation.grill}),
        TicketAssembling(prepped: <KitchenStation>{KitchenStation.grill}),
      );
      expect(
        TicketAssembling(prepped: <KitchenStation>{KitchenStation.grill})
            .hashCode,
        TicketAssembling(prepped: <KitchenStation>{KitchenStation.grill})
            .hashCode,
      );
      expect(
        TicketAssembling(prepped: <KitchenStation>{KitchenStation.grill}),
        isNot(
          TicketAssembling(prepped: <KitchenStation>{KitchenStation.starch}),
        ),
      );
      expect(const TicketWaiting(), isNot(const TicketPlated()));
    });

    test('an out-of-bounds assembling status is unrepresentable in debug', () {
      expect(
        () => TicketAssembling(prepped: const <KitchenStation>{}),
        throwsAssertionError,
      );
      expect(
        () => TicketAssembling(prepped: KitchenStation.values.toSet()),
        throwsAssertionError,
      );
    });
  });

  // -------------------------------------------------------------------
  // The ticket
  // -------------------------------------------------------------------

  group('ticket', () {
    test('an order becomes one instruction per station', () {
      final KitchenTicket t = ticket();
      expect(t.instructions.keys.toSet(), KitchenStation.values.toSet());
      expect(
        t.instructionFor(KitchenStation.grill)!.option,
        same(MawzoonCatalog.smokedEntrecote),
      );
      expect(
        t.instructionFor(KitchenStation.starch)!.option,
        same(MawzoonCatalog.wholeBulgur),
      );
      expect(
        t.instructionFor(KitchenStation.prep)!.option,
        same(MawzoonCatalog.mediterraneanSumacSalad),
      );
    });

    test('the ticket carries what changes how it is made or leaves', () {
      final KitchenTicket t = ticket(
        scale: PortionScale.athleticLoad,
        note: 'no onion',
      );
      expect(t.scale, PortionScale.athleticLoad);
      expect(t.mode, FulfilmentMode.delivery);
      expect(t.note, 'no onion');
      expect(t.status, const TicketWaiting());
    });

    test('a tap marks a station, and a second tap unmarks it', () {
      final KitchenTicket fresh = ticket();
      final KitchenTicket once = fresh.toggle(KitchenStation.grill);
      expect(once.isPrepped(KitchenStation.grill), isTrue);
      expect(once.status, isA<TicketAssembling>());

      final KitchenTicket back = once.toggle(KitchenStation.grill);
      expect(back.isPrepped(KitchenStation.grill), isFalse);
      expect(back.status, isA<TicketWaiting>());
    });

    test('toggling is immutable — the original ticket is untouched', () {
      final KitchenTicket fresh = ticket();
      fresh.toggle(KitchenStation.grill);
      expect(fresh.status, isA<TicketWaiting>());
      expect(fresh.isPrepped(KitchenStation.grill), isFalse);
    });

    test('three taps in any order reach plated', () {
      for (final List<KitchenStation> order in <List<KitchenStation>>[
        <KitchenStation>[
          KitchenStation.grill,
          KitchenStation.starch,
          KitchenStation.prep,
        ],
        <KitchenStation>[
          KitchenStation.prep,
          KitchenStation.grill,
          KitchenStation.starch,
        ],
        <KitchenStation>[
          KitchenStation.starch,
          KitchenStation.prep,
          KitchenStation.grill,
        ],
      ]) {
        KitchenTicket t = ticket();
        for (final KitchenStation station in order) {
          t = t.toggle(station);
        }
        expect(t.status, isA<TicketPlated>(), reason: '$order');
        expect(t.status.isPlated, isTrue);
      }
    });

    test('archiving is terminal — a stray tap cannot pull it back', () {
      final KitchenTicket plated = ticket()
          .toggle(KitchenStation.grill)
          .toggle(KitchenStation.starch)
          .toggle(KitchenStation.prep);
      final KitchenTicket archived = plated.archive();
      expect(archived.status, isA<TicketPackaging>());

      final KitchenTicket tapped = archived.toggle(KitchenStation.grill);
      expect(tapped.status, isA<TicketPackaging>());
      expect(identical(tapped, archived), isTrue);
    });

    test('identity is the code, the clock and the status', () {
      final KitchenTicket a = ticket();
      final KitchenTicket b = ticket();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(ticket(code: 'M-102')));
      expect(a, isNot(a.toggle(KitchenStation.grill)));
    });
  });

  // -------------------------------------------------------------------
  // The board
  // -------------------------------------------------------------------

  group('board controller', () {
    test('the line is oldest first, however tickets arrive', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);

      // Out of order on purpose: the line sorts, the caller does not.
      for (final KitchenTicket t in <KitchenTicket>[
        ticket(code: 'M-3', at: placed.add(const Duration(minutes: 6))),
        ticket(code: 'M-1', at: placed),
        ticket(code: 'M-2', at: placed.add(const Duration(minutes: 3))),
      ]) {
        board.receive(t);
      }

      expect(
        board.line.map((KitchenTicket t) => t.code),
        <String>['M-1', 'M-2', 'M-3'],
      );
    });

    test('a partial tap keeps the ticket on the line and rings nothing', () {
      final RecordingChime chime = RecordingChime();
      final KitchenBoardController board = KitchenBoardController(
        chime: chime,
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());

      int notifications = 0;
      board.addListener(() => notifications++);

      board
        ..toggleStation('M-101', KitchenStation.grill)
        ..toggleStation('M-101', KitchenStation.starch);

      expect(board.line, hasLength(1));
      expect(board.packaging, isEmpty);
      expect(board.line.single.status, isA<TicketAssembling>());
      expect(chime.rings, 0);
      expect(notifications, 2);
    });

    test('the third tap archives the ticket and rings exactly once', () {
      final RecordingChime chime = RecordingChime();
      final KitchenBoardController board = KitchenBoardController(
        chime: chime,
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());

      board
        ..toggleStation('M-101', KitchenStation.grill)
        ..toggleStation('M-101', KitchenStation.starch)
        ..toggleStation('M-101', KitchenStation.prep);

      expect(board.line, isEmpty);
      expect(board.packaging, hasLength(1));
      expect(board.packaging.single.code, 'M-101');
      expect(board.packaging.single.status, isA<TicketPackaging>());
      expect(chime.rings, 1);
    });

    test('a ticket that has left the line cannot be toggled back onto it', () {
      final RecordingChime chime = RecordingChime();
      final KitchenBoardController board = KitchenBoardController(
        chime: chime,
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());

      for (final KitchenStation station in KitchenStation.values) {
        board.toggleStation('M-101', station);
      }
      board.toggleStation('M-101', KitchenStation.grill);

      expect(board.line, isEmpty);
      expect(board.packaging, hasLength(1));
      expect(chime.rings, 1, reason: 'the chime is the completion, not a tap');
    });

    test('an undo before the last tap does not archive', () {
      final RecordingChime chime = RecordingChime();
      final KitchenBoardController board = KitchenBoardController(
        chime: chime,
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());

      board
        ..toggleStation('M-101', KitchenStation.grill)
        ..toggleStation('M-101', KitchenStation.starch)
        ..toggleStation('M-101', KitchenStation.starch)
        ..toggleStation('M-101', KitchenStation.prep);

      expect(board.line, hasLength(1));
      expect(board.packaging, isEmpty);
      expect(chime.rings, 0);
    });

    test('an unknown code is ignored rather than thrown', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());

      expect(
        () => board.toggleStation('nope', KitchenStation.grill),
        returnsNormally,
      );
      expect(board.line.single.status, isA<TicketWaiting>());
    });

    test('the newest finished ticket is at the head of the queue', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);
      for (final KitchenTicket t in <KitchenTicket>[
        ticket(code: 'M-1'),
        ticket(code: 'M-2', at: placed.add(const Duration(minutes: 2))),
      ]) {
        board.receive(t);
      }

      for (final KitchenStation station in KitchenStation.values) {
        board.toggleStation('M-1', station);
      }
      for (final KitchenStation station in KitchenStation.values) {
        board.toggleStation('M-2', station);
      }

      expect(
        board.packaging.map((KitchenTicket t) => t.code),
        <String>['M-2', 'M-1'],
      );
    });

    test('packing clears the ticket out of the queue', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());
      for (final KitchenStation station in KitchenStation.values) {
        board.toggleStation('M-101', station);
      }

      board.clearPackaged('M-101');
      expect(board.packaging, isEmpty);
    });

    test('the clock repaints a busy board and leaves an empty one alone', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);

      int notifications = 0;
      board.addListener(() => notifications++);

      board.tick();
      expect(notifications, 0, reason: 'an empty board has no ages to redraw');

      board.receive(ticket());
      notifications = 0;
      board.tick();
      expect(notifications, 1);
    });

    test('the clock ticks in seconds, not frames', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);
      expect(board.clockInterval.inSeconds, greaterThanOrEqualTo(1));
    });

    testWidgets('the clock fires on its own and stops at dispose',
        (WidgetTester tester) async {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        clockInterval: const Duration(seconds: 1),
        now: () => placed,
      )..receive(ticket());

      int notifications = 0;
      board.addListener(() => notifications++);

      await tester.pump(const Duration(seconds: 3));
      expect(notifications, greaterThanOrEqualTo(3));

      board.dispose();
      final int afterDispose = notifications;
      await tester.pump(const Duration(seconds: 3));
      expect(notifications, afterDispose, reason: 'a disposed board is silent');
    });

    test('a disposed board accepts nothing further', () {
      final RecordingChime chime = RecordingChime();
      final KitchenBoardController board = KitchenBoardController(
        chime: chime,
        now: () => placed,
      )..receive(ticket());
      board.dispose();

      expect(() => board.receive(ticket(code: 'M-9')), returnsNormally);
      expect(
        () => board.toggleStation('M-101', KitchenStation.grill),
        returnsNormally,
      );
      expect(() => board.clearPackaged('M-101'), returnsNormally);
      expect(board.line, hasLength(1));
      expect(chime.rings, 0);
    });

    test('the exposed lists cannot be mutated behind the board', () {
      final KitchenBoardController board = KitchenBoardController(
        chime: const SilentChime(),
        now: () => placed,
      );
      addTearDown(board.dispose);
      board.receive(ticket());

      expect(
        () => board.line.add(ticket(code: 'M-9')),
        throwsUnsupportedError,
      );
      expect(
        () => board.packaging.add(ticket(code: 'M-9')),
        throwsUnsupportedError,
      );
    });
  });

  // -------------------------------------------------------------------
  // The screen
  // -------------------------------------------------------------------

  group('board screen', () {
    Future<KitchenBoardController> pumpBoard(
      WidgetTester tester, {
      required KitchenChime chime,
      AppLanguage language = AppLanguage.arabic,
      DateTime? now,
      List<KitchenTicket> tickets = const <KitchenTicket>[],
    }) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final KitchenBoardController board = KitchenBoardController(
        chime: chime,
        clockInterval: const Duration(seconds: 10),
        now: () => now ?? placed,
      );
      for (final KitchenTicket t in tickets) {
        board.receive(t);
      }

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.of(
            Brightness.dark,
            language: language,
            fonts: const BundledMawzoonFonts(),
          ),
          locale: Locale(language.code),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          // Keyed per board: a re-pump with a different controller must build
          // a fresh screen rather than reusing the state — and therefore the
          // old board — of the one before it.
          home: _BoardHost(
            key: ValueKey<int>(identityHashCode(board)),
            board: board,
            child: KitchenBoardScreen(
              key: ValueKey<int>(identityHashCode(board)),
              controller: board,
            ),
          ),
        ),
      );
      await tester.pump();
      return board;
    }

    testWidgets('an empty board says so rather than showing nothing',
        (WidgetTester tester) async {
      await pumpBoard(tester, chime: const SilentChime());
      expect(find.byType(KitchenTicketCard), findsNothing);
    });

    testWidgets('a received ticket appears with its code',
        (WidgetTester tester) async {
      await pumpBoard(
        tester,
        chime: const SilentChime(),
        tickets: <KitchenTicket>[ticket()],
      );
      expect(find.byType(KitchenTicketCard), findsOneWidget);
      expect(find.text('M-101'), findsOneWidget);
    });

    testWidgets('three taps move the card to the packaging queue and chime',
        (WidgetTester tester) async {
      final RecordingChime chime = RecordingChime();
      final KitchenBoardController board = await pumpBoard(
        tester,
        chime: chime,
        tickets: <KitchenTicket>[ticket()],
      );

      for (final KitchenStation station in KitchenStation.values) {
        await tester.tap(find.text(station.label.ar).first);
        await tester.pump();
      }

      expect(chime.rings, 1);
      expect(board.line, isEmpty);
      expect(board.packaging, hasLength(1));
      expect(find.byType(KitchenTicketCard), findsNothing);
      expect(
        find.text('M-101'),
        findsOneWidget,
        reason: 'it is in the packaging queue now',
      );
    });

    testWidgets('station rows clear the gloved-hand touch target',
        (WidgetTester tester) async {
      await pumpBoard(
        tester,
        chime: const SilentChime(),
        tickets: <KitchenTicket>[ticket()],
      );

      for (final KitchenStation station in KitchenStation.values) {
        final Size row = tester.getSize(
          find
              .ancestor(
                of: find.text(station.label.ar).first,
                matching: find.byType(TactileFeedbackWell),
              )
              .first,
        );
        expect(
          row.height,
          greaterThanOrEqualTo(KdsMetrics.touchTarget),
          reason: '${station.name} is smaller than a gloved fingertip',
        );
      }
    });

    testWidgets('the urgency badge changes band with the clock, not the input',
        (WidgetTester tester) async {
      await pumpBoard(
        tester,
        chime: const SilentChime(),
        now: placed.add(const Duration(minutes: 20)),
        tickets: <KitchenTicket>[ticket()],
      );
      expect(find.text('20m'), findsOneWidget);
      expect(find.text(TicketUrgency.overdue.label.ar), findsOneWidget);
      expect(find.text(TicketUrgency.onPace.label.ar), findsNothing);
    });

    testWidgets('an on-pace ticket is a number, not a word',
        (WidgetTester tester) async {
      await pumpBoard(
        tester,
        chime: const SilentChime(),
        now: placed.add(const Duration(minutes: 4)),
        tickets: <KitchenTicket>[ticket()],
      );
      expect(find.text('4m'), findsOneWidget);
      for (final TicketUrgency band in TicketUrgency.values) {
        expect(
          find.text(band.label.ar),
          findsNothing,
          reason: 'a calm board does not spell out that it is calm',
        );
      }
    });

    testWidgets('the band is never carried by colour alone',
        (WidgetTester tester) async {
      // Disposed inline, not in a tearDown: the framework checks for a live
      // handle before tearDowns run, the same way it checks for pending timers.
      final SemanticsHandle handle = tester.ensureSemantics();

      for (final (Duration age, TicketUrgency band)
          in <(Duration, TicketUrgency)>[
        (const Duration(minutes: 2), TicketUrgency.onPace),
        (const Duration(minutes: 11), TicketUrgency.tightening),
        (const Duration(minutes: 31), TicketUrgency.overdue),
      ]) {
        await pumpBoard(
          tester,
          chime: const SilentChime(),
          now: placed.add(age),
          tickets: <KitchenTicket>[ticket()],
        );
        // A RegExp, not a string: inside a list the card's non-interactive
        // text merges into one node, so the band is a run within the card's
        // label ("M-101 … On pace, 2 min … Delivery") rather than a node of
        // its own. What matters is that the words are in the tree at all.
        expect(
          find.bySemanticsLabel(
            RegExp(RegExp.escape('${band.label.ar}, ${age.inMinutes} min')),
          ),
          findsOneWidget,
          reason: '${band.name} is unreadable without seeing its tone',
        );
      }

      handle.dispose();
    });

    testWidgets('the board reads in English too', (WidgetTester tester) async {
      await pumpBoard(
        tester,
        chime: const SilentChime(),
        language: AppLanguage.english,
        tickets: <KitchenTicket>[ticket()],
      );
      expect(find.text(KitchenStation.grill.label.en), findsOneWidget);
      expect(find.text(KitchenStation.starch.label.en), findsOneWidget);
      expect(find.text(KitchenStation.prep.label.en), findsOneWidget);
    });

    testWidgets(
      'the worst-case header fits the card rather than clipping',
      (WidgetTester tester) async {
        // Every optional element at once, in both scripts: an Athletic Load
        // chip, a delivery chip, and an overdue badge carrying its word. This
        // is the combination that overflowed a single-row header by 95px — and
        // an overflow on a kitchen board is information a cook cannot see.
        for (final AppLanguage language in AppLanguage.values) {
          await tester.binding.setSurfaceSize(const Size(1280, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final KitchenTicket worstCase = KitchenTicket.fromOrder(
            draft(scale: PortionScale.athleticLoad, note: 'extra sumac'),
            code: 'M-4018',
            placedAt: placed,
          );

          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.of(
                Brightness.dark,
                language: language,
                fonts: const BundledMawzoonFonts(),
              ),
              locale: Locale(language.code),
              supportedLocales: mawzoonSupportedLocales,
              localizationsDelegates: mawzoonLocalizationsDelegates,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: KdsMetrics.ticketWidth,
                    child: KitchenTicketCard(
                      key: ValueKey<String>(language.code),
                      ticket: worstCase,
                      // Well past the overdue threshold, so the badge carries
                      // its label as well as its number.
                      now: placed.add(const Duration(minutes: 41)),
                      onStationTapped: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: 'the card overflows in ${language.code}',
          );
          expect(find.text('41m'), findsOneWidget);
          expect(
            find.text(TicketUrgency.overdue.label.resolve(language)),
            findsOneWidget,
          );
          expect(
            find.text(FulfilmentMode.delivery.label.resolve(language)),
            findsOneWidget,
          );
          expect(
            find.text(PortionScale.athleticLoad.label.resolve(language)),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets('a guest note is carried to the line, not dropped at checkout',
        (WidgetTester tester) async {
      await pumpBoard(
        tester,
        chime: const SilentChime(),
        tickets: <KitchenTicket>[ticket(note: 'بدون بصل')],
      );
      expect(find.textContaining('بدون بصل'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // The kitchen app shell
  // -------------------------------------------------------------------

  group('kitchen app', () {
    testWidgets('starts on an empty board and owns its controller',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MawzoonKitchenApp());
      await tester.pump();

      expect(find.byType(KitchenBoardScreen), findsOneWidget);
      expect(find.byType(KitchenTicketCard), findsNothing);
      expect(find.text('لا طلبات على الخط'), findsOneWidget);

      // Replacing the tree disposes the app, and with it the board's clock.
      // If the shell leaked its controller, this test would fail on a pending
      // timer rather than passing quietly.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('is dark whatever the platform asks for',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MawzoonKitchenApp());
      await tester.pump();

      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(app.darkTheme, isNull);
      expect(app.theme!.brightness, Brightness.dark);
      expect(app.themeMode, ThemeMode.system);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('opens in the language the site was launched in',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MawzoonKitchenApp(language: AppLanguage.english),
      );
      await tester.pump();

      expect(find.text('Nothing on the line'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
