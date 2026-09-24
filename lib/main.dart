import 'dart:async';

import 'package:flutter/material.dart';

import 'core/localization/localized_text.dart';
import 'ui_primitives/menu/menu_scope.dart';
import 'features/manager_suite/application/manager_suite_controller.dart';
import 'features/manager_suite/domain/inventory_ledger.dart';
import 'features/mindful_satiety/application/reflection_controller.dart';
import 'features/mindful_satiety/data/reflection_notifier.dart';
import 'features/mindful_satiety/data/reflection_store.dart';
import 'features/mindful_satiety/presentation/reflection_surfaces.dart';
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

  /// The menu the back office publishes.
  ///
  /// In a real install this is a read-only view fed by whatever the manager
  /// app and the stock take write — the guest's phone does not host the back
  /// office, it subscribes to it. Held here so the wiring is real end to end:
  /// a component going below the safety buffer reaches the architect carousel
  /// through exactly the path it will in production.
  late final ManagerSuiteController _menu = ManagerSuiteController(
    ledger: InventoryLedger.stockedFor(60),
  );

  /// The post-meal loop. Everything it keeps stays on this phone.
  late final ReflectionController _reflections = ReflectionController(
    store: SharedPreferencesReflectionStore(),
    notifier: LocalReflectionNotifier(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_reflections.start());
  }

  @override
  void dispose() {
    _menu.dispose();
    _reflections.dispose();
    super.dispose();
  }

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
        home: ListenableBuilder(
          listenable: _menu,
          // One scope above the whole app rather than a lookup per screen.
          // Every screen showing a menu figure reads the same snapshot in the
          // same frame, so two parts of one screen can never disagree about
          // what a dish weighs or whether it can be ordered.
          builder: (BuildContext context, Widget? child) => MenuScope(
            book: _menu.book,
            availability: _menu.availability,
            child: ReflectionScope(controller: _reflections, child: child!),
          ),
          child: const OrderHomeScreen(),
        ),
      );
}
