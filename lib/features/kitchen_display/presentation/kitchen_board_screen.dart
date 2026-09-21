import 'package:flutter/material.dart';

import '../../../core/feedback/haptic_cue.dart';
import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../application/kitchen_board_controller.dart';
import '../domain/kitchen_station.dart';
import '../domain/kitchen_ticket.dart';
import 'kitchen_ticket_card.dart';

/// The kitchen display.
///
/// ## A work surface, not a product
///
/// This screen shares the brand's palette and type and almost nothing else of
/// its behaviour. There is no ambient glow, no balance lock, no spring on the
/// cards: a tool someone stands in front of for an eight-hour service should
/// hold still. Motion here is confined to the one thing that needs
/// acknowledging — a station being ticked.
///
/// Everything is sized for a metre back and a gloved hand: 64dp targets, type
/// a step up from the guest app, and urgency carried by a tone stripe legible
/// from across the room rather than by text someone has to walk over to read.
///
/// The board sorts oldest first and never re-sorts on its own, so the next
/// ticket to pick up is always the top-left one and the line never has to
/// re-read a board that rearranged itself mid-service.
class KitchenBoardScreen extends StatefulWidget {
  /// Creates the board.
  const KitchenBoardScreen({super.key, this.controller});

  /// An externally owned board, for tests or a restored service.
  final KitchenBoardController? controller;

  @override
  State<KitchenBoardScreen> createState() => _KitchenBoardScreenState();
}

class _KitchenBoardScreenState extends State<KitchenBoardScreen> {
  late final KitchenBoardController _board =
      widget.controller ?? KitchenBoardController();
  late final bool _ownsBoard = widget.controller == null;

  @override
  void dispose() {
    if (_ownsBoard) _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _board,
          builder: (BuildContext context, _) {
            final DateTime now = _board.now;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _Line(
                    tickets: _board.line,
                    now: now,
                    onStationTapped: _board.toggleStation,
                  ),
                ),
                _PackagingQueue(
                  tickets: _board.packaging,
                  onCleared: _board.clearPackaged,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.tickets,
    required this.now,
    required this.onStationTapped,
  });

  final List<KitchenTicket> tickets;
  final DateTime now;
  final void Function(String code, KitchenStation station) onStationTapped;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.all(context.space.comfortable),
          child: Row(
            children: <Widget>[
              MawzoonText(
                language == AppLanguage.arabic ? 'خط التحضير' : 'The line',
                style: context.type.display,
              ),
              SizedBox(width: context.space.base),
              MawzoonText(
                '${tickets.length}',
                style: context.type.display,
                color: context.colors.inkFaint,
              ),
            ],
          ),
        ),
        Expanded(
          child: tickets.isEmpty
              ? _Empty(
                  text: language == AppLanguage.arabic
                      ? 'لا طلبات على الخط'
                      : 'Nothing on the line',
                )
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    // One column per ticket-width of board. A kitchen tablet
                    // is landscape and wide; a phone-shaped single column
                    // would waste most of it.
                    final int columns =
                        (constraints.maxWidth / KdsMetrics.ticketWidth)
                            .floor()
                            .clamp(1, 5);

                    // Columns of independently scrolling lists rather than a
                    // grid of fixed-ratio cells. A grid has to pick one cell
                    // height for every ticket, and a ticket is not a fixed
                    // height: a plate with three kitchen notes and a guest
                    // request is taller than a plain one. Any ratio that fits
                    // the tallest wastes the board on the shortest, and any
                    // ratio that fits the shortest hides a station behind an
                    // in-card scroll — which is the one thing a board exists
                    // to prevent. Here every card is its natural height.
                    //
                    // Tickets are dealt across the columns, not down them, so
                    // the oldest is always in the leading corner and the next
                    // few are beside it: the line reads the top row, not a
                    // column it has to finish first.
                    return Padding(
                      padding: EdgeInsetsDirectional.symmetric(
                        horizontal: context.space.comfortable,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (int i = 0; i < columns; i++) ...<Widget>[
                            if (i > 0) SizedBox(width: context.space.base),
                            Expanded(
                              child: _LineColumn(
                                tickets: tickets,
                                columns: columns,
                                column: i,
                                now: now,
                                onStationTapped: onStationTapped,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// One column of the line: cards at their natural height, scrolling alone.
class _LineColumn extends StatelessWidget {
  const _LineColumn({
    required this.tickets,
    required this.columns,
    required this.column,
    required this.now,
    required this.onStationTapped,
  });

  /// Every ticket on the line, oldest first.
  final List<KitchenTicket> tickets;

  /// How many columns the board is dealing into.
  final int columns;

  /// Which column this is, from the leading edge.
  final int column;

  /// The board's clock.
  final DateTime now;

  /// Raised when a cook ticks a station.
  final void Function(String code, KitchenStation station) onStationTapped;

  /// How many tickets land in this column.
  int get _count =>
      (tickets.length ~/ columns) + (column < tickets.length % columns ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Keyed by the deal, so a resize rebuilds rather than restoring a scroll
      // offset that belonged to a different set of tickets.
      key: ValueKey<String>('kds.column.$column/$columns'),
      padding: EdgeInsetsDirectional.only(bottom: context.space.comfortable),
      itemCount: _count,
      separatorBuilder: (_, __) => SizedBox(height: context.space.base),
      itemBuilder: (BuildContext context, int row) {
        final KitchenTicket ticket = tickets[row * columns + column];
        return KitchenTicketCard(
          key: ValueKey<String>(ticket.code),
          ticket: ticket,
          now: now,
          onStationTapped: (KitchenStation station) =>
              onStationTapped(ticket.code, station),
        );
      },
    );
  }
}

/// Finished tickets, waiting to be packed.
class _PackagingQueue extends StatelessWidget {
  const _PackagingQueue({required this.tickets, required this.onCleared});

  final List<KitchenTicket> tickets;
  final ValueChanged<String> onCleared;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: context.colors.structure,
        border: Border(
          left: BorderSide(color: context.colors.hairline),
          right: BorderSide(color: context.colors.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.all(context.space.comfortable),
            child: MawzoonText(
              language == AppLanguage.arabic ? 'التغليف' : 'Packaging',
              style: context.type.sectionTitle,
            ),
          ),
          Expanded(
            child: tickets.isEmpty
                ? _Empty(
                    text: language == AppLanguage.arabic ? '—' : '—',
                  )
                : ListView.separated(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: context.space.base,
                    ),
                    itemCount: tickets.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: context.space.snug),
                    itemBuilder: (BuildContext context, int index) {
                      final KitchenTicket ticket = tickets[index];
                      return TactileFeedbackWell(
                        onPressed: () => onCleared(ticket.code),
                        pressCue: HapticCue.light,
                        semanticLabel: '${ticket.code} packed',
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: KdsMetrics.touchTarget,
                          ),
                          padding:
                              EdgeInsetsDirectional.all(context.space.base),
                          decoration: BoxDecoration(
                            color: context.colors.structureElevated,
                            borderRadius: context.space.controlRadius,
                            border: Border.all(color: context.colors.hairline),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.check_circle_rounded,
                                color: context.colors.olive,
                                size: 22,
                              ),
                              SizedBox(width: context.space.snug),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  ticket.code,
                                  style: context.type.dishName
                                      .copyWith(color: context.colors.ink),
                                ),
                              ),
                              const Spacer(),
                              MawzoonText(
                                ticket.mode.label.resolve(language),
                                style: context.type.tagLabel,
                                color: context.colors.inkFaint,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: MawzoonText(
          text,
          style: context.type.body,
          color: context.colors.inkFaint,
        ),
      );
}
