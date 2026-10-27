import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/localization/localized_text.dart';
import 'features/counter_desk/application/counter_controller.dart';
import 'features/counter_desk/domain/counter_payment.dart';
import 'features/counter_desk/domain/unpaid_order.dart';
import 'features/counter_desk/presentation/counter_screen.dart';
import 'features/staff_auth/domain/staff_auth.dart';
import 'features/staff_auth/presentation/staff_gate.dart';
import 'services/supabase_counter_desk.dart';
import 'services/supabase_service.dart';
import 'services/supabase_staff_auth.dart';
import 'services/supabase_unpaid_orders.dart';
import 'ui_primitives/theme/theme.dart';

/// Entry point for the cashier's tablet:
///
/// ```sh
/// flutter run -t lib/main_counter.dart
/// ```
///
/// A separate target for the same reason as the kitchen's: the cashier never
/// sees cook screens or stock, and the guest bundle never ships this.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]),
  );
  await SupabaseService.initialize();
  runApp(MawzoonCounterApp(auth: SupabaseStaffAuth()));
}

/// The counter application shell. Light, Arabic: it sits in a lit shop.
class MawzoonCounterApp extends StatelessWidget {
  /// Creates the app. [feed] and [desk] are for tests; they default to live.
  const MawzoonCounterApp({
    required this.auth,
    this.language = AppLanguage.arabic,
    this.feed,
    this.desk,
    super.key,
  });

  /// Staff sign-in; the list shows only behind it.
  final StaffAuth auth;

  /// The language this counter reads.
  final AppLanguage language;

  /// Where unpaid orders come from. Null: live.
  final UnpaidOrderFeed? feed;

  /// Where "paid" goes. Null: live.
  final CounterDesk? desk;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mawzoon Counter',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(language: language),
        locale: Locale(language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: StaffGate(
          auth: auth,
          subtitle: const LocalizedText(
            ar: 'الصندوق — دخول فريق العمل',
            en: 'Counter — staff sign-in',
          ),
          note: const LocalizedText(
            ar: 'تبقى الشاشة مسجّلة حتى يخرج المدير منها. الحسابات يضيفها المدير.',
            en: 'The screen stays signed in until the manager signs it out. '
                'The manager adds accounts.',
          ),
          signedIn: (BuildContext context) => _LiveCounter(
            feed: feed ?? SupabaseUnpaidOrders(),
            desk: desk ?? SupabaseCounterDesk(),
          ),
        ),
      );
}

/// Owns the controller, so signing out (removing this widget) also closes the
/// realtime channel.
class _LiveCounter extends StatefulWidget {
  const _LiveCounter({required this.feed, required this.desk});

  final UnpaidOrderFeed feed;
  final CounterDesk desk;

  @override
  State<_LiveCounter> createState() => _LiveCounterState();
}

class _LiveCounterState extends State<_LiveCounter> {
  late final CounterController _controller =
      CounterController(feed: widget.feed, desk: widget.desk)..start();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CounterScreen(controller: _controller);
}
