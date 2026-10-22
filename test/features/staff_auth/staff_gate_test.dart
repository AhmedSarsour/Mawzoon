import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/features/staff_auth/domain/staff_auth.dart';
import 'package:mawzoon/features/staff_auth/presentation/staff_gate.dart';
import 'package:mawzoon/ui_primitives/motion/motion.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

final class _FakeAuth implements StaffAuth {
  _FakeAuth({this.now = const StaffSignedOut()});

  StaffAccess now;
  (StaffAccess?, StaffSignInFailure?) next = (const StaffSignedIn(), null);
  final List<String> calls = <String>[];

  @override
  Future<StaffAccess> current() async => now;

  @override
  Future<(StaffAccess?, StaffSignInFailure?)> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn $email');
    return next;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    now = const StaffSignedOut();
  }
}

Finder _button(String label) => find.byWidgetPredicate(
      (Widget w) => w is TactileFeedbackWell && w.semanticLabel == label,
    );

Future<void> _pump(WidgetTester tester, StaffAuth auth) async {
  await tester.binding.setSurfaceSize(const Size(1024, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(fonts: _fonts),
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      home: StaffGate(
        auth: auth,
        subtitle: const LocalizedText(
          ar: 'شاشة المطبخ — دخول فريق العمل',
          en: 'Kitchen screen — staff sign-in',
        ),
        note: const LocalizedText(ar: 'الحسابات يضيفها المدير.', en: 'x'),
        signedIn: (BuildContext context) => const Text('BOARD'),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'cook@mawzoon.sa');
  await tester.enterText(find.byType(TextField).at(1), 'secret');
  await tester.pump();
}

void main() {
  testWidgets('a stored staff session goes straight to the board',
      (WidgetTester t) async {
    await _pump(t, _FakeAuth(now: const StaffSignedIn()));
    expect(find.text('BOARD'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('sign-in is live only with an email and a password',
      (WidgetTester t) async {
    final _FakeAuth auth = _FakeAuth();
    await _pump(t, auth);
    expect(t.widget<TactileFeedbackWell>(_button('دخول')).enabled, isFalse);
    await _fill(t);
    expect(t.widget<TactileFeedbackWell>(_button('دخول')).enabled, isTrue);

    await t.tap(_button('دخول'));
    await t.pump();
    await t.pump();
    expect(auth.calls, <String>['signIn cook@mawzoon.sa']);
    expect(find.text('BOARD'), findsOneWidget);
  });

  testWidgets('a wrong password says so, without saying which part',
      (WidgetTester t) async {
    final _FakeAuth auth = _FakeAuth()
      ..next = (null, StaffSignInFailure.wrongCredentials);
    await _pump(t, auth);
    await _fill(t);
    await t.tap(_button('دخول'));
    await t.pump();
    await t.pump();
    expect(find.text('البريد أو كلمة المرور غير صحيحة'), findsOneWidget);
    expect(find.text('BOARD'), findsNothing);

    await t.enterText(find.byType(TextField).at(1), 'secret2');
    await t.pump();
    expect(
      find.text('البريد أو كلمة المرور غير صحيحة'),
      findsNothing,
      reason: 'the message clears once they try again',
    );
  });

  testWidgets('offline says it could not connect', (WidgetTester t) async {
    final _FakeAuth auth = _FakeAuth()
      ..next = (null, StaffSignInFailure.unreachable);
    await _pump(t, auth);
    await _fill(t);
    await t.tap(_button('دخول'));
    await t.pump();
    await t.pump();
    expect(find.text('تعذّر الاتصال — حاول مجددًا'), findsOneWidget);
  });

  testWidgets(
      'not on the team: names the account, never opens the board, '
      'and "another account" signs out', (WidgetTester t) async {
    final _FakeAuth auth =
        _FakeAuth(now: const StaffNotOnTeam('guest@example.com'));
    await _pump(t, auth);
    expect(find.text('هذا الحساب ليس من فريق العمل'), findsOneWidget);
    expect(find.text('guest@example.com'), findsOneWidget);
    expect(find.text('BOARD'), findsNothing);

    await t.tap(_button('الدخول بحساب آخر'));
    await t.pump();
    await t.pump();
    expect(auth.calls, <String>['signOut']);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets(
    'golden: kitchen sign-in',
    (WidgetTester t) async {
      await _pump(t, _FakeAuth());
      await _fill(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/staff_sign_in.png'),
      );
    },
    tags: <String>['golden'],
  );

  testWidgets(
    'golden: not on the team',
    (WidgetTester t) async {
      await _pump(t, _FakeAuth(now: const StaffNotOnTeam('guest@example.com')));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/staff_not_on_team.png'),
      );
    },
    tags: <String>['golden'],
  );
}
