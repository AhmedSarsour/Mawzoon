import 'package:flutter/material.dart';

import 'core/localization/localized_text.dart';
import 'features/order_home/presentation/order_home_screen.dart';
import 'ui_primitives/theme/theme.dart';

/// Entry point.
void main() => runApp(const MawzoonApp());

/// The Mawzoon application shell.
///
/// Themes are built once per language rather than per build: a fresh
/// [ThemeData] compares unequal to the last one, and `AnimatedTheme` would
/// then lerp every colour in the tree on every rebuild.
class MawzoonApp extends StatefulWidget {
  /// Creates the app.
  const MawzoonApp({super.key});

  @override
  State<MawzoonApp> createState() => _MawzoonAppState();
}

class _MawzoonAppState extends State<MawzoonApp> {
  AppLanguage _language = AppLanguage.arabic;
  late ThemeData _light = AppTheme.light(language: _language);
  late ThemeData _dark = AppTheme.dark(language: _language);

  /// Switches the app language and rebuilds both themes for the new script.
  void setLanguage(AppLanguage language) {
    if (_language == language) return;
    setState(() {
      _language = language;
      _light = AppTheme.light(language: language);
      _dark = AppTheme.dark(language: language);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mawzoon',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        locale: Locale(_language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: const OrderHomeScreen(),
      );
}
