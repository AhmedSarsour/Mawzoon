import 'package:flutter/material.dart';

import '../../../core/feedback/haptic_cue.dart';
import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/mawzoon_colors.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../domain/kitchen_station.dart';
import '../domain/kitchen_ticket.dart';

/// Sizing for a screen read across a kitchen rather than held in a hand.
///
/// A phone's 48dp target assumes a bare fingertip at arm's length. A line cook
/// is a metre back, often gloved, and not looking directly at the tablet when
/// they reach for it — so every target here is 64dp and the type runs a step
/// larger than the guest app's.
abstract final class KdsMetrics {
  /// Minimum edge of anything tappable on the line.
  static const double touchTarget = 64;

  /// Width a ticket wants before the board adds another column.
  static const double ticketWidth = 340;
}

/// A time badge that informs without alarming.
///
/// No flashing, no red, no siren. A kitchen under pressure already knows it is
/// under pressure; an alarm that fires every busy service is noise the line
/// learns to ignore, and then it is worse than nothing. The three bands are
/// the plate's own macro tones — olive, maize, terracotta — so the board reads
/// in the same palette as the product.
class UrgencyBadge extends StatelessWidget {
  /// Creates the badge.
  const UrgencyBadge({required this.age, required this.urgency, super.key});

  /// How long the ticket has been on the line.
  final Duration age;

  /// The band it falls in.
  final TicketUrgency urgency;

  /// The tone for [urgency], drawn from the macro palette.
  static Color toneFor(TicketUrgency urgency, MawzoonColors colors) =>
      switch (urgency) {
        TicketUrgency.onPace => colors.fiber,
        TicketUrgency.tightening => colors.carb,
        TicketUrgency.overdue => colors.protein,
      };

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final Color tone = toneFor(urgency, context.colors);
    final String band = urgency.label.resolve(language);

    return Semantics(
      // The tone is the fast channel, but it must not be the only one: a cook
      // with a colour vision deficiency, or a board washed out by a service
      // window at noon, still has to be able to tell the bands apart.
      label: '$band, ${age.inMinutes} min',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.base,
          vertical: context.space.tight + 2,
        ),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.16),
          borderRadius: context.space.pillRadius,
          border: Border.all(color: tone.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Directionality(
              // "12m" is a Latin expression: it must not be reordered in
              // Arabic, whatever the surrounding paragraph direction is.
              textDirection: TextDirection.ltr,
              child: Text(
                '${age.inMinutes}m',
                style: context.type.capsuleLabel
                    .copyWith(color: tone, fontWeight: FontWeight.w700),
              ),
            ),
            // Named only when it is late. On pace and tightening are read off
            // the tone and the number; spelling them out on every ticket would
            // turn the board into a wall of words the line stops seeing, which
            // is exactly how an alarm becomes noise. Overdue is stated plainly,
            // once, because that is the one a cook must not misread.
            if (urgency == TicketUrgency.overdue) ...<Widget>[
              SizedBox(width: context.space.micro),
              MawzoonText(
                band,
                style: context.type.tagLabel,
                color: tone,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One order on the line, split into its three stations.
class KitchenTicketCard extends StatelessWidget {
  /// Creates a ticket card.
  const KitchenTicketCard({
    required this.ticket,
    required this.now,
    required this.onStationTapped,
    super.key,
  });

  /// The ticket shown.
  final KitchenTicket ticket;

  /// The board's clock, so every card on screen agrees about the time.
  final DateTime now;

  /// Called when a station is tapped.
  final ValueChanged<KitchenStation> onStationTapped;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final TicketUrgency urgency = ticket.urgencyAt(now);
    final Color tone = UrgencyBadge.toneFor(urgency, context.colors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.structure,
        borderRadius: context.space.surfaceRadius,
        border: Border.all(color: context.colors.hairline),
        boxShadow: context.elevation.resting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // A single tone stripe rather than a coloured card: the urgency is
          // legible from across the room without tinting the food names.
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(context.space.radiusSurface),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.all(context.space.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The two things read from a metre back get the top line to
                // themselves and are never crowded off it: which ticket this
                // is, and how long it has been waiting.
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Directionality(
                        // A ticket code is a Latin expression. It keeps its
                        // own order inside an Arabic board.
                        textDirection: TextDirection.ltr,
                        child: Text(
                          ticket.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.sectionTitle.copyWith(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: context.space.snug),
                    UrgencyBadge(age: ticket.ageAt(now), urgency: urgency),
                  ],
                ),
                SizedBox(height: context.space.tight),
                // Everything that changes how the plate is built or how it
                // leaves the pass, on its own line and wrapped. A chip pushed
                // off the edge of a narrow column is a missed Athletic Load,
                // which is a re-fire — so this wraps rather than clips.
                Wrap(
                  spacing: context.space.snug,
                  runSpacing: context.space.micro,
                  children: <Widget>[
                    if (ticket.scale.nominalKilocalories > 600)
                      _Chip(
                        text: ticket.scale.label.resolve(language),
                        tone: context.colors.ember,
                      ),
                    _Chip(
                      text: ticket.mode.label.resolve(language),
                      tone: context.colors.inkFaint,
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final KitchenStation station in KitchenStation.line)
            _StationRow(
              station: station,
              instruction: ticket.instructionFor(station),
              prepped: ticket.isPrepped(station),
              onTap: () => onStationTapped(station),
            ),
          if (ticket.note != null)
            Padding(
              padding: EdgeInsetsDirectional.all(context.space.base),
              child: MawzoonText(
                ticket.note!,
                style: context.type.caption,
                color: context.colors.ember,
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.snug,
          vertical: context.space.micro,
        ),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(context.space.radiusSubtle),
        ),
        child: MawzoonText(
          text,
          style: context.type.tagLabel,
          color: tone,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

/// One station's line on a ticket, tappable to mark it prepped.
class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.instruction,
    required this.prepped,
    required this.onTap,
  });

  final KitchenStation station;
  final StationInstruction? instruction;
  final bool prepped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = context.appLanguage;
    final StationInstruction? spec = instruction;
    if (spec == null) return const SizedBox.shrink();

    final Color tone =
        context.colors.toneForSegmentOrdinal(station.segment.ordinal);

    return TactileFeedbackWell(
      onPressed: onTap,
      selected: prepped,
      // A commitment, not a scroll: the cook is telling the board something.
      pressCue: HapticCue.light,
      semanticLabel: '${station.label.resolve(language)}, '
          '${spec.option.name.resolve(language)}, '
          '${spec.displayGrams} grams'
          '${prepped ? ', done' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: KdsMetrics.touchTarget),
        padding: EdgeInsetsDirectional.all(context.space.base),
        decoration: BoxDecoration(
          color: prepped
              ? context.colors.olive.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border(
            top: BorderSide(color: context.colors.hairline),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StationMark(prepped: prepped, tone: tone),
            SizedBox(width: context.space.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      MawzoonText(
                        station.label.resolve(language),
                        style: context.type.tagLabel,
                        color: context.colors.inkFaint,
                      ),
                      const Spacer(),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          // Cooked weight, which is what the guest was shown.
                          '${spec.displayGrams} g',
                          style: context.type.capsuleLabel.copyWith(
                            color: prepped
                                ? context.colors.inkFaint
                                : context.colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  MawzoonText(
                    spec.option.name.resolve(language),
                    style: context.type.dishName,
                    color:
                        prepped ? context.colors.inkFaint : context.colors.ink,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: context.space.micro),
                  Wrap(
                    spacing: context.space.snug,
                    runSpacing: context.space.micro,
                    children: <Widget>[
                      _Chip(
                        text: spec.method.label.resolve(language),
                        tone: tone,
                      ),
                      if (spec.hasDoneness)
                        _Chip(
                          text: spec.doneness.label.resolve(language),
                          tone: tone,
                        ),
                    ],
                  ),
                  if (spec.note != null) ...<Widget>[
                    SizedBox(height: context.space.tight),
                    MawzoonText(
                      spec.note!.resolve(language),
                      style: context.type.caption,
                      color: context.colors.inkSoft,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tick a cook aims at.
class _StationMark extends StatelessWidget {
  const _StationMark({required this.prepped, required this.tone});

  final bool prepped;
  final Color tone;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: prepped ? context.colors.olive : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: prepped ? context.colors.olive : tone,
            width: 2,
          ),
        ),
        child: prepped
            ? Icon(
                Icons.check_rounded,
                size: 20,
                color: context.colors.onOlive,
              )
            : null,
      );
}
