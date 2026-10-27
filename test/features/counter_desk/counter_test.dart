import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/pricing/money.dart';
import 'package:mawzoon/features/counter_desk/application/counter_controller.dart';
import 'package:mawzoon/features/counter_desk/domain/counter_payment.dart';
import 'package:mawzoon/features/counter_desk/domain/unpaid_order.dart';
import 'package:mawzoon/features/counter_desk/presentation/counter_screen.dart';
import 'package:mawzoon/features/staff_auth/domain/staff_auth.dart';
import 'package:mawzoon/main_counter.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();
final DateTime _now = DateTime(2026, 10, 22, 19, 0);

UnpaidOrder _order(int n, {int cents = 4900, int dueInMin = 40}) => UnpaidOrder(
      id: 'id-$n',
      number: n,
      total: Money(cents),
      createdAt: _now.subtract(const Duration(minutes: 5)),
      dueAt: _now.add(Duration(minutes: dueInMin)),
      title: 'صحن موزون',
    );

final class _Feed implements UnpaidOrderFeed {
  final StreamController<List<UnpaidOrder>> out =
      StreamController<List<UnpaidOrder>>.broadcast();
  int refreshes = 0;

  @override
  Stream<List<UnpaidOrder>> watch() => out.stream;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  void dispose() => unawaited(out.close());
}

final class _Desk implements CounterDesk {
  CounterPayResult answer = CounterPayResult.paid;
  Completer<CounterPayResult>? hold;
  final List<String> marked = <String>[];

  @override
  Future<CounterPayResult> markPaid(String orderId) {
    marked.add(orderId);
    return hold?.future ?? Future<CounterPayResult>.value(answer);
  }
}

Finder _well(String label) => find.byWidgetPredicate(
      (Widget w) => w is TactileFeedbackWell && w.semanticLabel == label,
    );

class _Rig {
  _Rig(this.tester);

  final WidgetTester tester;
  final _Feed feed = _Feed();
  final _Desk desk = _Desk();
  late final CounterController controller = CounterController(
    feed: feed,
    desk: desk,
    clock: () => _now,
  );

  Future<void> show(List<UnpaidOrder> orders) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    controller.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(fonts: _fonts),
        locale: const Locale('ar'),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: CounterScreen(controller: controller),
      ),
    );
    feed.out.add(orders);
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  }
}

void main() {
  testWidgets('lists code, total and age with a big paid button',
      (WidgetTester tester) async {
    final _Rig rig = _Rig(tester);
    await rig.show(<UnpaidOrder>[_order(12), _order(13, cents: 6400)]);
    expect(find.text('M-12'), findsOneWidget);
    expect(find.text('49.00 ₪'), findsOneWidget);
    expect(find.text('64.00 ₪'), findsOneWidget);
    expect(find.text('قبل 5 د'), findsNWidgets(2));
    expect(_well('تم الدفع'), findsNWidgets(2));
    await rig.finish();
  });

  testWidgets('search matches the order number', (WidgetTester tester) async {
    final _Rig rig = _Rig(tester);
    await rig.show(<UnpaidOrder>[_order(12), _order(13), _order(112)]);
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    expect(find.text('M-12'), findsOneWidget);
    expect(find.text('M-112'), findsOneWidget);
    expect(find.text('M-13'), findsNothing);

    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();
    expect(find.text('لا طلب بهذا الرقم'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('empty list says so', (WidgetTester tester) async {
    final _Rig rig = _Rig(tester);
    await rig.show(<UnpaidOrder>[]);
    expect(find.text('لا طلبات تنتظر الدفع'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('a soon-to-expire order says when; a past-due one has no button',
      (WidgetTester tester) async {
    final _Rig rig = _Rig(tester);
    await rig.show(<UnpaidOrder>[
      _order(9, dueInMin: 7),
      _order(7, dueInMin: -1),
    ]);
    expect(find.text('ينتهي بعد 7 د'), findsOneWidget);
    expect(find.text('انتهى'), findsOneWidget);
    expect(_well('تم الدفع'), findsOneWidget, reason: 'only M-9 is payable');
    await rig.finish();
  });

  group('confirming', () {
    testWidgets('paid asks first; back marks nothing',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(tester);
      await rig.show(<UnpaidOrder>[_order(12)]);
      await tester.tap(_well('تم الدفع'));
      await tester.pump();
      expect(find.text('استلمت 49.00 ₪؟'), findsOneWidget);
      expect(rig.desk.marked, isEmpty);

      await tester.tap(_well('رجوع'));
      await tester.pump();
      expect(find.text('استلمت 49.00 ₪؟'), findsNothing);
      expect(rig.desk.marked, isEmpty);
      await rig.finish();
    });

    testWidgets('yes marks that order and refreshes the list',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(tester);
      await rig.show(<UnpaidOrder>[_order(12), _order(13)]);
      await tester.tap(_well('تم الدفع').first);
      await tester.pump();
      await tester.tap(_well('نعم'));
      await tester.pump();
      await tester.pump();

      expect(rig.desk.marked, <String>['id-12']);
      expect(find.text('تم الدفع M-12 — ذهب للمطبخ'), findsOneWidget);
      expect(rig.feed.refreshes, 1);
      await rig.finish();
    });

    testWidgets('a second tap while waiting marks once',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(tester);
      rig.desk.hold = Completer<CounterPayResult>();
      await rig.show(<UnpaidOrder>[_order(12)]);
      await tester.tap(_well('تم الدفع'));
      await tester.pump();
      await tester.tap(_well('نعم'));
      await tester.pump();
      await rig.controller.confirm(_order(12));
      expect(rig.desk.marked, hasLength(1));

      rig.desk.hold!.complete(CounterPayResult.paid);
      await tester.pump();
      await rig.finish();
    });

    const Map<CounterPayResult, String> messages = <CounterPayResult, String>{
      CounterPayResult.alreadyPaid: 'M-12 مدفوع مسبقًا',
      CounterPayResult.expired: 'M-12 انتهى — اطلب من الزبون طلبًا جديدًا',
      CounterPayResult.cancelled: 'M-12 أُلغي',
      CounterPayResult.cardRequired: 'M-12 بالبطاقة فقط',
      CounterPayResult.notFound: 'M-12 غير موجود',
    };
    for (final MapEntry<CounterPayResult, String> e in messages.entries) {
      testWidgets('${e.key.name}: says so and closes the question',
          (WidgetTester tester) async {
        final _Rig rig = _Rig(tester);
        rig.desk.answer = e.key;
        await rig.show(<UnpaidOrder>[_order(12)]);
        await tester.tap(_well('تم الدفع'));
        await tester.pump();
        await tester.tap(_well('نعم'));
        await tester.pump();
        await tester.pump();
        expect(find.text(e.value), findsOneWidget);
        expect(find.text('استلمت 49.00 ₪؟'), findsNothing);
        await rig.finish();
      });
    }

    testWidgets('no connection: keeps the question so yes can be tapped again',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(tester);
      rig.desk.answer = CounterPayResult.unreachable;
      await rig.show(<UnpaidOrder>[_order(12)]);
      await tester.tap(_well('تم الدفع'));
      await tester.pump();
      await tester.tap(_well('نعم'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('لا اتصال'), findsOneWidget);
      expect(find.text('استلمت 49.00 ₪؟'), findsOneWidget);

      rig.desk.answer = CounterPayResult.paid;
      await tester.tap(_well('نعم'));
      await tester.pump();
      await tester.pump();
      expect(rig.desk.marked, <String>['id-12', 'id-12']);
      await rig.finish();
    });

    testWidgets('an order paid elsewhere drops its open question',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(tester);
      await rig.show(<UnpaidOrder>[_order(12), _order(13)]);
      await tester.tap(_well('تم الدفع').first);
      await tester.pump();
      rig.feed.out.add(<UnpaidOrder>[_order(13)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('استلمت 49.00 ₪؟'), findsNothing);
      expect(rig.controller.confirmingId, isNull);
      await rig.finish();
    });
  });

  test('searchByNumber ignores non-digits and keeps all on empty', () {
    final List<UnpaidOrder> all = <UnpaidOrder>[_order(12), _order(13)];
    expect(searchByNumber(all, ''), all);
    expect(searchByNumber(all, 'M-'), all);
    expect(searchByNumber(all, 'M-13').single.number, 13);
  });

  testWidgets('signed out, the counter shows sign-in and never the list',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _Feed feed = _Feed();
    await tester.pumpWidget(
      MawzoonCounterApp(auth: _SignedOut(), feed: feed, desk: _Desk()),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('الصندوق — دخول فريق العمل'), findsOneWidget);
    expect(feed.out.hasListener, isFalse);
    expect(find.byType(CounterScreen), findsNothing);
  });
}

final class _SignedOut implements StaffAuth {
  @override
  Future<StaffAccess> current() async => const StaffSignedOut();

  @override
  Future<(StaffAccess?, StaffSignInFailure?)> signIn({
    required String email,
    required String password,
  }) async =>
      (null, StaffSignInFailure.wrongCredentials);

  @override
  Future<void> signOut() async {}
}
