import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../cart_checkout/domain/delivery_address.dart';
import '../../cart_checkout/domain/order_draft.dart';
import 'kitchen_station.dart';

/// How long a ticket has been on the line, expressed without alarm.
///
/// No flashing, no red, no siren. A kitchen under pressure does not need to be
/// told it is under pressure — it needs to know which ticket to pick up next,
/// and an alarm that fires on every busy service stops being information and
/// becomes noise the line learns to ignore.
///
/// The three bands reuse the plate's own macro tones, so the board is lit in
/// the same palette as the product: olive, maize, terracotta.
enum TicketUrgency {
  /// Under eight minutes. On pace.
  onPace(
    ceiling: Duration(minutes: 8),
    label: LocalizedText(ar: 'ضمن الوقت', en: 'On pace'),
  ),

  /// Eight to fifteen minutes. Worth picking up next.
  tightening(
    ceiling: Duration(minutes: 15),
    label: LocalizedText(ar: 'يقترب', en: 'Tightening'),
  ),

  /// Past fifteen minutes. Stated plainly, once.
  overdue(
    ceiling: Duration(days: 1),
    label: LocalizedText(ar: 'متأخر', en: 'Overdue'),
  );

  const TicketUrgency({required this.ceiling, required this.label});

  /// The age at which this band gives way to the next.
  final Duration ceiling;

  /// How the badge reads.
  final LocalizedText label;

  /// The band [age] falls in.
  static TicketUrgency forAge(Duration age) {
    for (final TicketUrgency band in TicketUrgency.values) {
      if (age < band.ceiling) return band;
    }
    return TicketUrgency.overdue;
  }
}

/// Where a ticket is in its life on the line.
///
/// Four states, exhaustive and flat, so a board that forgets to handle one
/// does not compile.
sealed class TicketStatus {
  const TicketStatus();

  /// Derives the status from which stations have been prepped.
  ///
  /// The single transition function. A status is never constructed directly,
  /// so "waiting" carrying two finished stations is unrepresentable.
  factory TicketStatus.from({
    required Set<KitchenStation> prepped,
    required bool packaged,
  }) {
    if (packaged) return const TicketPackaging();
    if (prepped.isEmpty) return const TicketWaiting();
    if (prepped.length < KitchenStation.values.length) {
      return TicketAssembling(prepped: prepped);
    }
    return const TicketPlated();
  }

  /// The stations finished so far.
  Set<KitchenStation> get prepped;

  /// Whether every station is finished.
  bool get isPlated => prepped.length == KitchenStation.values.length;

  /// Whether the ticket has left the line.
  bool get isArchived => this is TicketPackaging;
}

/// On the board, untouched.
final class TicketWaiting extends TicketStatus {
  /// Creates the waiting status.
  const TicketWaiting();

  @override
  Set<KitchenStation> get prepped => const <KitchenStation>{};

  @override
  String toString() => 'TicketWaiting()';

  @override
  bool operator ==(Object other) => other is TicketWaiting;

  @override
  int get hashCode => (TicketWaiting).hashCode;
}

/// One or two stations finished.
final class TicketAssembling extends TicketStatus {
  /// Creates the assembling status.
  ///
  /// Prefer [TicketStatus.from]: this asserts the bounds rather than trusting
  /// them.
  TicketAssembling({required this.prepped})
      : assert(prepped.isNotEmpty, 'nothing prepped is TicketWaiting'),
        assert(
          prepped.length < 3,
          'every station prepped is TicketPlated',
        );

  @override
  final Set<KitchenStation> prepped;

  /// The stations still to do.
  Set<KitchenStation> get remaining =>
      KitchenStation.values.toSet().difference(prepped);

  @override
  String toString() => 'TicketAssembling(${prepped.length}/3)';

  @override
  bool operator ==(Object other) =>
      other is TicketAssembling &&
      other.prepped.length == prepped.length &&
      other.prepped.containsAll(prepped);

  @override
  int get hashCode => Object.hashAllUnordered(prepped);
}

/// All three stations finished. The moment the chime belongs to.
final class TicketPlated extends TicketStatus {
  /// Creates the plated status.
  const TicketPlated();

  @override
  Set<KitchenStation> get prepped => KitchenStation.values.toSet();

  @override
  String toString() => 'TicketPlated()';

  @override
  bool operator ==(Object other) => other is TicketPlated;

  @override
  int get hashCode => (TicketPlated).hashCode;
}

/// Archived off the line and into the packaging queue.
final class TicketPackaging extends TicketStatus {
  /// Creates the packaging status.
  const TicketPackaging();

  @override
  Set<KitchenStation> get prepped => KitchenStation.values.toSet();

  @override
  String toString() => 'TicketPackaging()';

  @override
  bool operator ==(Object other) => other is TicketPackaging;

  @override
  int get hashCode => (TicketPackaging).hashCode;
}

/// One order, as the line sees it.
///
/// Immutable: every tap produces a new ticket, so a board can never render a
/// status computed from a set of prepped stations that has since changed.
final class KitchenTicket {
  /// Creates a ticket.
  const KitchenTicket({
    required this.code,
    required this.placedAt,
    required this.instructions,
    required this.scale,
    required this.mode,
    this.status = const TicketWaiting(),
    this.note,
  }) : assert(code.length > 0, 'a ticket needs a code');

  /// Builds a ticket from a placed order.
  factory KitchenTicket.fromOrder(
    OrderDraft order, {
    required String code,
    required DateTime placedAt,
  }) {
    assert(
      order.selection.isComplete,
      'an incomplete plate should never reach the line',
    );
    return KitchenTicket(
      code: code,
      placedAt: placedAt,
      scale: order.selection.scale,
      mode: order.mode,
      note: order.note,
      instructions: <KitchenStation, StationInstruction>{
        for (final StationInstruction instruction in order.components.map(
          (option) => StationInstruction.from(option, order.selection.scale),
        ))
          instruction.station: instruction,
      },
    );
  }

  /// The short code called out at the pass.
  final String code;

  /// When the order was placed.
  final DateTime placedAt;

  /// What each station has to make.
  final Map<KitchenStation, StationInstruction> instructions;

  /// The portion, which the line needs: an Athletic Load is a different weigh.
  final PortionScale scale;

  /// Delivery or pickup, which sets how it leaves the pass.
  final FulfilmentMode mode;

  /// Where the ticket is in its life.
  final TicketStatus status;

  /// Anything the guest asked for.
  final String? note;

  /// How long this ticket has been on the line at [now].
  Duration ageAt(DateTime now) => now.difference(placedAt);

  /// The urgency band at [now].
  TicketUrgency urgencyAt(DateTime now) => TicketUrgency.forAge(ageAt(now));

  /// Whether [station] is finished.
  bool isPrepped(KitchenStation station) => status.prepped.contains(station);

  /// The instruction for [station].
  StationInstruction? instructionFor(KitchenStation station) =>
      instructions[station];

  /// Marks [station] finished, or unmarks it if it already was.
  ///
  /// Reversible on purpose. A cook who taps the wrong station on a busy line
  /// should be able to undo it in one tap, not call a manager.
  KitchenTicket toggle(KitchenStation station) {
    if (status.isArchived) return this;
    final Set<KitchenStation> next = <KitchenStation>{...status.prepped};
    if (!next.remove(station)) next.add(station);
    return copyWith(
      status: TicketStatus.from(prepped: next, packaged: false),
    );
  }

  /// Moves the ticket into the packaging queue.
  KitchenTicket archive() => copyWith(
        status: TicketStatus.from(
          prepped: KitchenStation.values.toSet(),
          packaged: true,
        ),
      );

  /// Returns a copy with the given fields replaced.
  KitchenTicket copyWith({TicketStatus? status, String? note}) => KitchenTicket(
        code: code,
        placedAt: placedAt,
        instructions: instructions,
        scale: scale,
        mode: mode,
        status: status ?? this.status,
        note: note ?? this.note,
      );

  @override
  String toString() => 'KitchenTicket($code, $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitchenTicket &&
          other.code == code &&
          other.placedAt == placedAt &&
          other.status == status;

  @override
  int get hashCode => Object.hash(code, placedAt, status);
}
