import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/menu/mawzoon_catalog.dart';
import 'package:mawzoon/core/pricing/money.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_draft.dart';
import 'package:mawzoon/features/cart_checkout/domain/order_placement.dart';
import 'package:mawzoon/features/cart_checkout/presentation/order_gateway_scope.dart';
import 'package:mawzoon/features/order_home/presentation/order_home_screen.dart';
import 'package:mawzoon/features/order_tracking/domain/tracked_order.dart';
import 'package:mawzoon/features/order_tracking/presentation/order_status_screen.dart';
import 'package:mawzoon/features/plate_builder/application/plate_builder_controller.dart';
import 'package:mawzoon/features/plate_builder/domain/plate_selection.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

final DateTime _due = DateTime(2026, 10, 22, 19, 45);

TrackedOrder _order(
  OrderStage stage, {
  CancelReason? reason,
  DateTime? due,
}) =>
    TrackedOrder(
      id: 'o-1',
      number: 12,
      stage: stage,
      total: const Money(4900),
      dueAt: due ?? _due,
      cancelReason: reason,
      title: 'صحن موزون',
    );

final class _FakeTracker implements OrderTracker {
  final StreamController<TrackedOrder?> updates =
      StreamController<TrackedOrder?>.broadcast();
  TrackedOrder? open;
  CancelResult cancelAnswer = CancelResult.cancelled;
  final List<String> cancelled = <String>[];

  @override
  Stream<TrackedOrder?> watch(String orderId) => updates.stream;

  @override
  Future<TrackedOrder?> openOrder() async => open;

  @override
  Future<CancelResult> cancel(String orderId) async {
    cancelled.add(orderId);
    return cancelAnswer;
  }
}

Widget _app(Widget home, {OrderGatewayScope Function(Widget)? scope}) =>
    MaterialApp(
      theme: AppTheme.light(fonts: _fonts),
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      builder: scope == null
          ? null
          : (BuildContext context, Widget? app) => scope(app!),
      home: home,
    );

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Sends [next] down the stream and lets the frame that shows it run.
Future<void> _push(
  WidgetTester tester,
  _FakeTracker tracker,
  TrackedOrder next,
) async {
  tracker.updates.add(next);
  await tester.pump();
  await tester.pump();
}

Finder _well(String label) => find.byWidgetPredicate(
      (Widget w) => w is TactileFeedbackWell && w.semanticLabel == label,
    );

void main() {
  group('receipt (unpaid)', () {
    testWidgets('shows the code, total, and the SERVER\'s expiry time',
        (WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          OrderStatusScreen(
            orderId: 'o-1',
            initial: _order(OrderStage.awaitingPayment, due: _due),
          ),
        ),
      );

      expect(find.text('M-12'), findsOneWidget);
      expect(find.text('49.00 ₪'), findsOneWidget);
      expect(find.textContaining('19:45'), findsOneWidget);
      expect(find.textContaining('ادفع عند الصندوق'), findsOneWidget);
    });

    testWidgets('never says the kitchen has it, and says prep starts after pay',
        (WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          OrderStatusScreen(
            orderId: 'o-1',
            initial: _order(OrderStage.awaitingPayment),
          ),
        ),
      );

      expect(find.textContaining('نبدأ التحضير بعد الدفع'), findsOneWidget);
      expect(find.textContaining('في المطبخ'), findsNothing);
      expect(find.textContaining('تم استلام'), findsNothing);
      expect(find.textContaining('نحضّر صحنك الآن'), findsNothing);
    });

    testWidgets('a different server deadline moves the shown time',
        (WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          OrderStatusScreen(
            orderId: 'o-1',
            initial: _order(
              OrderStage.awaitingPayment,
              due: DateTime(2026, 10, 22, 7, 5),
            ),
          ),
        ),
      );
      expect(find.textContaining('07:05'), findsOneWidget);
    });
  });

  group('tracking', () {
    testWidgets('moves waiting → paid → making → ready from the order row',
        (WidgetTester tester) async {
      await _phone(tester);
      final _FakeTracker tracker = _FakeTracker();
      await tester.pumpWidget(
        _app(
          OrderStatusScreen(
            orderId: 'o-1',
            initial: _order(OrderStage.awaitingPayment),
            tracker: tracker,
          ),
        ),
      );
      expect(find.textContaining('طلبك محجوز'), findsOneWidget);

      await _push(tester, tracker, _order(OrderStage.paid));
      expect(find.textContaining('تم الدفع — طلبك في الطابور'), findsOneWidget);
      expect(find.text('إلغاء الطلب'), findsNothing);

      await _push(tester, tracker, _order(OrderStage.making));
      expect(find.text('نحضّر صحنك الآن'), findsOneWidget);

      await _push(tester, tracker, _order(OrderStage.ready));
      expect(find.textContaining('صحنك جاهز'), findsOneWidget);
    });

    testWidgets('an expiry sweep shows "expired", not "cancelled by you"',
        (WidgetTester tester) async {
      await _phone(tester);
      final _FakeTracker tracker = _FakeTracker();
      await tester.pumpWidget(
        _app(
          OrderStatusScreen(
            orderId: 'o-1',
            initial: _order(OrderStage.awaitingPayment),
            tracker: tracker,
          ),
        ),
      );
      tracker.updates.add(
        _order(OrderStage.cancelled, reason: CancelReason.expired),
      );
      await tester.pump();
      expect(find.text('انتهى وقت الطلب'), findsOneWidget);
      expect(find.textContaining('لم يُحضَّر شيء'), findsOneWidget);
    });
  });

  group('cancel while unpaid', () {
    Future<_FakeTracker> pump(WidgetTester tester) async {
      await _phone(tester);
      final _FakeTracker tracker = _FakeTracker();
      await tester.pumpWidget(
        _app(
          OrderStatusScreen(
            orderId: 'o-1',
            initial: _order(OrderStage.awaitingPayment),
            tracker: tracker,
          ),
        ),
      );
      return tracker;
    }

    testWidgets('asks first, then cancels', (WidgetTester tester) async {
      final _FakeTracker tracker = await pump(tester);
      await tester.tap(_well('إلغاء الطلب'));
      await tester.pumpAndSettle();
      expect(tracker.cancelled, isEmpty, reason: 'a dialog comes first');

      await tester.tap(find.widgetWithText(TextButton, 'إلغاء الطلب'));
      await tester.pumpAndSettle();
      expect(tracker.cancelled, <String>['o-1']);
      expect(find.text('تم إلغاء الطلب'), findsOneWidget);
    });

    testWidgets('"back" in the dialog cancels nothing',
        (WidgetTester tester) async {
      final _FakeTracker tracker = await pump(tester);
      await tester.tap(_well('إلغاء الطلب'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'رجوع'));
      await tester.pumpAndSettle();
      expect(tracker.cancelled, isEmpty);
      expect(find.textContaining('طلبك محجوز'), findsOneWidget);
    });

    testWidgets('paid a moment ago: says so, stays on the receipt',
        (WidgetTester tester) async {
      final _FakeTracker tracker = await pump(tester);
      tracker.cancelAnswer = CancelResult.tooLate;
      await tester.tap(_well('إلغاء الطلب'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'إلغاء الطلب'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تم دفع الطلب للتو'), findsOneWidget);
      expect(find.text('تم إلغاء الطلب'), findsNothing);
    });

    testWidgets('no connection: stays, can try again',
        (WidgetTester tester) async {
      final _FakeTracker tracker = await pump(tester);
      tracker.cancelAnswer = CancelResult.unreachable;
      await tester.tap(_well('إلغاء الطلب'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'إلغاء الطلب'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تعذّر الاتصال'), findsOneWidget);
      expect(_well('إلغاء الطلب'), findsOneWidget);
    });
  });

  group('from the home screen', () {
    final PlateSelection plate = PlateSelection.empty
        .select(MawzoonCatalog.herbGrilledBreast)
        .select(MawzoonCatalog.steamedBasmati)
        .select(MawzoonCatalog.charredGardenVeggies);

    Future<void> openHome(
      WidgetTester tester, {
      required OrderGateway gateway,
      required _FakeTracker tracker,
    }) async {
      await _phone(tester);
      final PlateBuilderController controller = PlateBuilderController()
        ..replaceSelection(plate);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          OrderHomeScreen(controller: controller),
          scope: (Widget child) => OrderGatewayScope(
            gateway: gateway,
            tracker: tracker,
            child: child,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> checkout(WidgetTester tester) async {
      await tester.tap(find.text('إتمام الطلب'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(_well('تأكيد الطلب'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('placing an order opens the receipt, not the old snackbar',
        (WidgetTester tester) async {
      await openHome(
        tester,
        gateway: _OneAnswer(
          OrderPlaced(
            orderId: 'o-9',
            orderNumber: 104,
            total: const Money(5635),
            awaitingPayment: true,
            paymentDueAt: DateTime(2026, 10, 22, 20, 15),
          ),
        ),
        tracker: _FakeTracker(),
      );
      await checkout(tester);
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(OrderStatusScreen), findsOneWidget);
      expect(find.text('M-104'), findsOneWidget);
      expect(find.textContaining('20:15'), findsOneWidget);
      expect(find.textContaining('تم استلام طلبك'), findsNothing);
    });

    testWidgets('unpaid order already open: jumps to it, keeps the plate',
        (WidgetTester tester) async {
      await openHome(
        tester,
        gateway: _OneAnswer(
          const OrderRefused(
            RefusalReason.unpaidOrderOpen,
            openOrderId: 'o-7',
            openOrderNumber: 7,
          ),
        ),
        tracker: _FakeTracker(),
      );
      await checkout(tester);
      await tester.pump(const Duration(milliseconds: 600));

      final OrderStatusScreen shown =
          tester.widget(find.byType(OrderStatusScreen));
      expect(shown.orderId, 'o-7');
    });

    testWidgets('reopening the app with an open order lands on it',
        (WidgetTester tester) async {
      final _FakeTracker tracker = _FakeTracker()
        ..open = _order(OrderStage.making);
      await openHome(
        tester,
        gateway: _OneAnswer(const OrderUnreachable()),
        tracker: tracker,
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(OrderStatusScreen), findsOneWidget);
      expect(find.text('نحضّر صحنك الآن'), findsOneWidget);
    });

    testWidgets('no open order: the menu stays', (WidgetTester tester) async {
      await openHome(
        tester,
        gateway: _OneAnswer(const OrderUnreachable()),
        tracker: _FakeTracker(),
      );
      expect(find.byType(OrderStatusScreen), findsNothing);
    });
  });
}

final class _OneAnswer implements OrderGateway {
  _OneAnswer(this.answer);

  final PlaceOrderOutcome answer;

  @override
  Future<PlaceOrderOutcome> place(
    OrderDraft draft, {
    required String idempotencyKey,
  }) async =>
      answer;
}
