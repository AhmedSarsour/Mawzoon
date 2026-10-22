import 'package:flutter/foundation.dart';

import '../core/menu/ingredient_option.dart';
import '../core/menu/mawzoon_catalog.dart';
import '../core/nutrition/portion_scale.dart';
import '../features/cart_checkout/domain/delivery_address.dart';
import '../features/kitchen_display/domain/kitchen_station.dart';
import '../features/kitchen_display/domain/kitchen_ticket.dart';

/// The columns the board reads, in one query with the plate embedded.
const String kitchenOrderColumns =
    'id, order_number, order_type, status, note, created_at, '
    'order_items(id, protein_id, carb_id, fiber_id, volume_type, station_status)';

/// Order statuses still on the board (line or packaging).
const List<String> kitchenActiveStatuses = <String>[
  'PENDING',
  'ACCEPTED',
  'ASSEMBLING',
  'READY',
];

/// What the board needs to write back for one ticket.
@immutable
final class KitchenTicketRef {
  /// Creates a reference.
  const KitchenTicketRef({
    required this.orderId,
    required this.itemId,
    required this.status,
  });

  /// `orders.id`.
  final String orderId;

  /// `order_items.id` — the plate whose stations are tapped.
  final String itemId;

  /// `orders.status` when last read.
  final String status;
}

/// One snapshot: the tickets, and how to address each one.
typedef KitchenSnapshot = ({
  List<KitchenTicket> tickets,
  Map<String, KitchenTicketRef> refs,
});

PortionScale _scale(String? volume) => volume == 'ATHLETIC'
    ? PortionScale.athleticLoad
    : PortionScale.standardBalance;

/// Rows from `orders` (with `order_items` embedded) as tickets.
///
/// One plate per order today, as `place_order` writes. An order whose plate
/// names a component this build doesn't know is skipped, loudly, rather than
/// shown with a station missing — a cook can't make what the ticket can't say.
KitchenSnapshot kitchenSnapshotFromRows(List<dynamic> rows) {
  final List<KitchenTicket> tickets = <KitchenTicket>[];
  final Map<String, KitchenTicketRef> refs = <String, KitchenTicketRef>{};

  for (final Map<String, dynamic> order in rows.cast<Map<String, dynamic>>()) {
    final List<dynamic> items =
        order['order_items'] as List<dynamic>? ?? const <dynamic>[];
    if (items.isEmpty) continue;
    final Map<String, dynamic> item = items.first as Map<String, dynamic>;
    final PortionScale scale = _scale(item['volume_type'] as String?);

    final List<IngredientOption?> options = <IngredientOption?>[
      for (final String key in <String>['protein_id', 'carb_id', 'fiber_id'])
        MawzoonCatalog.optionById(item[key] as String),
    ];
    if (options.contains(null)) {
      debugPrint(
        'kitchen: order ${order['order_number']} names an unknown component',
      );
      continue;
    }

    final Map<String, dynamic> stations =
        (item['station_status'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
    final String status = order['status'] as String;
    final String code = 'M-${order['order_number']}';

    tickets.add(
      KitchenTicket(
        code: code,
        placedAt: DateTime.parse(order['created_at'] as String).toLocal(),
        scale: scale,
        mode: order['order_type'] == 'DELIVERY'
            ? FulfilmentMode.delivery
            : FulfilmentMode.pickup,
        note: order['note'] as String?,
        instructions: <KitchenStation, StationInstruction>{
          for (final IngredientOption option
              in options.cast<IngredientOption>())
            KitchenStation.forSegment(option.segment):
                StationInstruction.from(option, scale),
        },
        status: TicketStatus.from(
          prepped: <KitchenStation>{
            for (final KitchenStation s in KitchenStation.values)
              if (stations[s.name] == true) s,
          },
          packaged: status == 'READY',
        ),
      ),
    );
    refs[code] = KitchenTicketRef(
      orderId: order['id'] as String,
      itemId: item['id'] as String,
      status: status,
    );
  }
  tickets.sort(
    (KitchenTicket a, KitchenTicket b) => a.placedAt.compareTo(b.placedAt),
  );
  return (tickets: tickets, refs: refs);
}
