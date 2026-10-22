import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/localization/localized_text.dart';
import 'features/kitchen_display/application/kitchen_board_controller.dart';
import 'features/staff_auth/domain/staff_auth.dart';
import 'features/staff_auth/presentation/staff_gate.dart';
import 'features/kitchen_display/presentation/kitchen_board_screen.dart';
import 'services/supabase_kitchen_feed.dart';
import 'services/supabase_service.dart';
import 'services/supabase_staff_auth.dart';
import 'ui_primitives/theme/theme.dart';

/// Entry point for the kitchen tablet.
///
/// ## Why this is a second target and not a route
///
/// The board is a different product for a different person on a different
/// device. A guest must not be able to reach it by deep link or by a stray
/// back gesture, and the line must not be able to reach a checkout sheet. A
/// separate entry point makes that a build-time fact rather than a guard
/// someone has to remember to write:
///
/// ```sh
/// flutter run -t lib/main_kitchen.dart
/// ```
///
/// It also keeps the guest bundle free of the board, which never ships to a
/// phone.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A kitchen tablet is mounted, landscape, and must not sleep mid-service.
  // Both are properties of the room, so they are set here rather than by a
  // screen that might be popped.
  unawaited(
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]),
  );
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

  // Live orders need a staff session (RLS), so the board sits behind sign-in.
  // If Supabase failed to start, sign-in says it can't connect.
  await SupabaseService.initialize();
  runApp(MawzoonKitchenApp(auth: SupabaseStaffAuth()));
}

/// The kitchen display application shell.
///
/// Dark only. A board runs for an eight-hour service in a room where the
/// lighting is over the pass, not over the screen, and a light theme on a
/// glossy tablet under a hood light is a mirror. There is no language toggle
/// either: the line's language is set when the site is opened, not per
/// service, so it is a launch argument rather than a control someone can
/// knock with an elbow.
class MawzoonKitchenApp extends StatefulWidget {
  /// Creates the kitchen app.
  const MawzoonKitchenApp({
    super.key,
    this.language = AppLanguage.arabic,
    this.auth,
  });

  /// The language this site's line reads.
  final AppLanguage language;

  /// Staff sign-in, behind which the board shows live orders. Null: an empty
  /// board filled by hand, for tests and demos.
  final StaffAuth? auth;

  @override
  State<MawzoonKitchenApp> createState() => _MawzoonKitchenAppState();
}

class _MawzoonKitchenAppState extends State<MawzoonKitchenApp> {
  /// Built once. A fresh [ThemeData] compares unequal to the last one, and
  /// `AnimatedTheme` would then lerp every colour in the tree on every
  /// rebuild — which on a board that ticks every ten seconds is every ten
  /// seconds, all service.
  late final ThemeData _theme = AppTheme.dark(language: widget.language);

  /// The demo board (no [MawzoonKitchenApp.auth]). The board outlives any
  /// screen showing it, so the app owns it.
  KitchenBoardController? _demo;

  @override
  void dispose() {
    _demo?.dispose();
    super.dispose();
  }

  Widget _home() {
    final StaffAuth? auth = widget.auth;
    if (auth == null) {
      return KitchenBoardScreen(controller: _demo ??= KitchenBoardController());
    }
    return StaffGate(
      auth: auth,
      subtitle: const LocalizedText(
        ar: 'شاشة المطبخ — دخول فريق العمل',
        en: 'Kitchen screen — staff sign-in',
      ),
      note: const LocalizedText(
        ar: 'تبقى الشاشة مسجّلة حتى يخرج المدير منها. الحسابات يضيفها المدير.',
        en: 'The screen stays signed in until the manager signs it out. '
            'The manager adds accounts.',
      ),
      signedIn: (BuildContext context) => const _LiveBoard(),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mawzoon Kitchen',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        locale: Locale(widget.language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: _home(),
      );
}

/// The board on live orders. Owns its controller, so signing out (which
/// removes this widget) also closes the realtime channel.
class _LiveBoard extends StatefulWidget {
  const _LiveBoard();

  @override
  State<_LiveBoard> createState() => _LiveBoardState();
}

class _LiveBoardState extends State<_LiveBoard> {
  late final KitchenBoardController _board =
      KitchenBoardController(feed: SupabaseKitchenFeed());

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KitchenBoardScreen(controller: _board);
}
