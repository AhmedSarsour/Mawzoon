import 'package:flutter/widgets.dart';

import '../../order_tracking/domain/tracked_order.dart';
import '../domain/guest_phone.dart';
import '../domain/order_placement.dart';

/// Hands the checkout the [OrderGateway] that reaches the kitchen.
///
/// Absent in tests and previews, where the sheet confirms locally — the same
/// optional-scope pattern as `ReflectionScope`.
class OrderGatewayScope extends InheritedWidget {
  /// Creates the scope.
  const OrderGatewayScope({
    required this.gateway,
    required super.child,
    this.onMenuStale,
    this.phoneMemory,
    this.tracker,
    super.key,
  });

  /// Reads and cancels the guest's own orders (receipt and tracking screens).
  final OrderTracker? tracker;

  /// Where the guest's delivery phone is remembered between orders.
  final PhoneMemory? phoneMemory;

  /// Where orders go.
  final OrderGateway gateway;

  /// Called when the server's answer shows the local menu is out of date
  /// (something sold out, or the menu changed), so it can be refreshed now
  /// rather than at the next poll.
  final VoidCallback? onMenuStale;

  /// The nearest scope, or null.
  static OrderGatewayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrderGatewayScope>();

  @override
  bool updateShouldNotify(OrderGatewayScope oldWidget) =>
      gateway != oldWidget.gateway ||
      onMenuStale != oldWidget.onMenuStale ||
      phoneMemory != oldWidget.phoneMemory ||
      tracker != oldWidget.tracker;
}
