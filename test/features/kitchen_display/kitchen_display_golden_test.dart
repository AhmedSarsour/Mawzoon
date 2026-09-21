@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/menu/ingredient_option.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/kitchen_display/application/kitchen_board_controller.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_station.dart';
import 'package:mawzoon/features/kitchen_display/domain/kitchen_ticket.dart';
import 'package:mawzoon/features/kitchen_display/presentation/kitchen_board_screen.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

/// Renders the kitchen board at tablet size so the one thing that cannot be
/// asserted — whether a cook a metre back can read it — can be looked at.
///
/// The service below is deliberately mid-rush: one ticket in every urgency
/// band, one half-assembled, one at Athletic Load, one with a guest note, and
/// two already in the packaging queue. A board that is legible here is legible
/// on a bad Thursday.
void main() {
  const BundledMawzoonFonts fonts = BundledMawzoonFonts();

  /// The clock the board is frozen against.
  final DateTime now = DateTime.utc(2026, 3, 14, 20, 15);

  KitchenTicket ticketFor({
    required String code,
    required int minutesAgo,
    required ProteinOption protein,
    required CarbOption carb,
    required FiberOption fiber,
    PortionScale scale = PortionScale.standardBalance,
    FulfilmentMode mode = FulfilmentMode.delivery,
    String? note,
    Set<KitchenStation> prepped = const <KitchenStation>{},
  }) {
    KitchenTicket ticket = KitchenTicket.fromOrder(
      OrderDraft(
        selection: PlateSelection(
          protein: protein,
          carb: carb,
          fiber: fiber,
          scale: scale,
        ),
        mode: mode,
        payment: PaymentMethod.wallet,
        address: mode == FulfilmentMode.delivery
            ? const DeliveryAddress(
                id: 'addr.demo',
                label: LocalizedText(ar: 'البيت', en: 'Home'),
                line: '12 Olive St',
                district: 'Al Olaya',
              )
            : null,
        note: note,
      ),
      code: code,
      placedAt: now.subtract(Duration(minutes: minutesAgo)),
    );
    for (final KitchenStation station in prepped) {
      ticket = ticket.toggle(station);
    }
    return ticket;
  }

  KitchenBoardController service() {
    final KitchenBoardController board = KitchenBoardController(
      chime: const SilentChime(),
      clockInterval: const Duration(minutes: 5),
      now: () => now,
    );

    final List<KitchenTicket> rush = <KitchenTicket>[
      ticketFor(
        code: 'M-418',
        minutesAgo: 2,
        protein: MawzoonCatalog.herbGrilledBreast,
        carb: MawzoonCatalog.toastedQuinoa,
        fiber: MawzoonCatalog.charredGardenVeggies,
      ),
      ticketFor(
        code: 'M-417',
        minutesAgo: 6,
        mode: FulfilmentMode.pickup,
        protein: MawzoonCatalog.smashedLeanBeef,
        carb: MawzoonCatalog.airFriedSpicedPotatoes,
        fiber: MawzoonCatalog.mediterraneanSumacSalad,
        prepped: <KitchenStation>{KitchenStation.prep},
      ),
      ticketFor(
        code: 'M-415',
        minutesAgo: 11,
        scale: PortionScale.athleticLoad,
        protein: MawzoonCatalog.smokedEntrecote,
        carb: MawzoonCatalog.sweetPotatoWedges,
        fiber: MawzoonCatalog.charredGardenVeggies,
        prepped: <KitchenStation>{KitchenStation.grill, KitchenStation.starch},
      ),
      ticketFor(
        code: 'M-412',
        minutesAgo: 19,
        protein: MawzoonCatalog.koftaSpicedMince,
        carb: MawzoonCatalog.wholeBulgur,
        fiber: MawzoonCatalog.mediterraneanSumacSalad,
        note: 'بدون بصل في السلطة',
      ),
    ];
    for (final KitchenTicket ticket in rush) {
      board.receive(ticket);
    }

    // Two finished earlier in the rush, still waiting to be packed.
    for (final String code in <String>['M-409', 'M-411']) {
      board.receive(
        ticketFor(
          code: code,
          minutesAgo: 24,
          protein: MawzoonCatalog.marinatedThighs,
          carb: MawzoonCatalog.steamedBasmati,
          fiber: MawzoonCatalog.charredGardenVeggies,
        ),
      );
      for (final KitchenStation station in KitchenStation.values) {
        board.toggleStation(code, station);
      }
    }

    return board;
  }

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    AppLanguage language = AppLanguage.arabic,
    Size size = const Size(1280, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final KitchenBoardController board = service();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(brightness, language: language, fonts: fonts),
        locale: Locale(language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: _BoardHost(
          board: board,
          child: KitchenBoardScreen(controller: board),
        ),
      ),
    );
    // The board has no ambient animation by design, so a single settle is
    // enough — unlike any screen carrying the plate, which breathes forever.
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('board, dark, arabic', (WidgetTester t) async {
    await shoot(t, 'kds_dark', brightness: Brightness.dark);
  });

  testWidgets('board, light, arabic', (WidgetTester t) async {
    await shoot(t, 'kds_light', brightness: Brightness.light);
  });

  testWidgets('board, dark, english', (WidgetTester t) async {
    await shoot(
      t,
      'kds_en',
      brightness: Brightness.dark,
      language: AppLanguage.english,
    );
  });

  testWidgets('board, a narrow tablet held upright', (WidgetTester t) async {
    await shoot(
      t,
      'kds_portrait',
      brightness: Brightness.dark,
      size: const Size(834, 1112),
    );
  });
}

/// Disposes the board with the tree, since the screen does not own it.
class _BoardHost extends StatefulWidget {
  const _BoardHost({required this.board, required this.child});

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
