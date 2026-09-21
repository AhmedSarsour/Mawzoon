import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/localization/localized_text.dart';
import 'features/kitchen_display/application/kitchen_board_controller.dart';
import 'features/kitchen_display/presentation/kitchen_board_screen.dart';
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
void main() {
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

  runApp(const MawzoonKitchenApp());
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
  const MawzoonKitchenApp({super.key, this.language = AppLanguage.arabic});

  /// The language this site's line reads.
  final AppLanguage language;

  @override
  State<MawzoonKitchenApp> createState() => _MawzoonKitchenAppState();
}

class _MawzoonKitchenAppState extends State<MawzoonKitchenApp> {
  /// Built once. A fresh [ThemeData] compares unequal to the last one, and
  /// `AnimatedTheme` would then lerp every colour in the tree on every
  /// rebuild — which on a board that ticks every ten seconds is every ten
  /// seconds, all service.
  late final ThemeData _theme = AppTheme.dark(language: widget.language);

  /// The board outlives any screen showing it, so the app owns it.
  ///
  /// This is the seam a real install replaces: today the board starts empty
  /// and is filled by whatever calls [KitchenBoardController.receive] — an
  /// order stream, a POS bridge, a websocket. The board does not care where a
  /// ticket came from, which is why that decision is not made in here.
  late final KitchenBoardController _board = KitchenBoardController();

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mawzoon Kitchen',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        locale: Locale(widget.language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: KitchenBoardScreen(controller: _board),
      );
}
