import 'package:flutter/material.dart';

import 'core/localization/localized_text.dart';
import 'features/manager_suite/application/manager_suite_controller.dart';
import 'features/manager_suite/domain/inventory_ledger.dart';
import 'features/manager_suite/presentation/manager_shell.dart';
import 'features/staff_auth/domain/staff_auth.dart';
import 'features/staff_auth/presentation/staff_gate.dart';
import 'services/supabase_back_office.dart';
import 'services/supabase_service.dart';
import 'services/supabase_staff_auth.dart';
import 'ui_primitives/theme/theme.dart';

/// Entry point for the back office.
///
/// A third target, for the same reason the kitchen board is a second one: this
/// screen changes a published nutrition figure and can take a dish off the
/// menu, and neither capability should be one deep link away from a guest's
/// phone.
///
/// ```sh
/// flutter run -t lib/main_manager.dart
/// ```
///
/// Unlike the board, this one follows the platform's light and dark setting.
/// A back office is an office: it is used at a desk, in daylight, beside other
/// software, and forcing it dark to match the kitchen would be styling over
/// ergonomics.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The real store needs a staff session (RLS), so the office sits behind
  // sign-in. If Supabase failed to start, sign-in says it can't connect.
  await SupabaseService.initialize();
  runApp(MawzoonManagerApp(auth: SupabaseStaffAuth()));
}

/// The manager application shell.
class MawzoonManagerApp extends StatefulWidget {
  /// Creates the manager app.
  const MawzoonManagerApp({
    super.key,
    this.language = AppLanguage.arabic,
    this.signedInAs = 'manager',
    this.auth,
  });

  /// Staff sign-in, behind which the office runs on the server's store.
  /// Null: a full demo store, for tests and demos.
  final StaffAuth? auth;

  /// The language this site's office reads.
  final AppLanguage language;

  /// Who is signed in, stamped onto every calibration they commit.
  final String signedInAs;

  @override
  State<MawzoonManagerApp> createState() => _MawzoonManagerAppState();
}

class _MawzoonManagerAppState extends State<MawzoonManagerApp> {
  late final ThemeData _light = AppTheme.light(language: widget.language);
  late final ThemeData _dark = AppTheme.dark(language: widget.language);

  /// The demo suite (no [MawzoonManagerApp.auth]): a full store, so the
  /// office is inspectable without a server.
  ManagerSuiteController? _demo;

  @override
  void dispose() {
    _demo?.dispose();
    super.dispose();
  }

  Widget _home() {
    final StaffAuth? auth = widget.auth;
    if (auth == null) {
      return ManagerShell(
        controller: _demo ??= ManagerSuiteController(
          ledger: InventoryLedger.stockedFor(60),
          signedInAs: widget.signedInAs,
        ),
      );
    }
    return StaffGate(
      auth: auth,
      subtitle: const LocalizedText(
        ar: 'الإدارة — دخول فريق العمل',
        en: 'Back office — staff sign-in',
      ),
      note: const LocalizedText(
        ar: 'الحسابات يضيفها المدير.',
        en: 'The manager adds accounts.',
      ),
      signedIn: (BuildContext context) => const _LiveOffice(),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mawzoon Manager',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        locale: Locale(widget.language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: _home(),
      );
}

/// The office on the server's store. Owns its controller, so leaving it
/// closes the realtime channel.
class _LiveOffice extends StatefulWidget {
  const _LiveOffice();

  @override
  State<_LiveOffice> createState() => _LiveOfficeState();
}

class _LiveOfficeState extends State<_LiveOffice> {
  late final ManagerSuiteController _suite = ManagerSuiteController(
    // Calibrations are stamped with the account that made them.
    signedInAs: SupabaseService.client.auth.currentUser?.email ?? 'manager',
    store: SupabaseBackOffice(),
  );

  @override
  void dispose() {
    _suite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ManagerShell(controller: _suite);
}
