import 'dart:async';

import 'package:flutter/material.dart';

import 'core/localization/localized_text.dart';
import 'core/menu/recipe_book.dart';
import 'features/cart_checkout/domain/order_placement.dart';
import 'features/cart_checkout/presentation/order_gateway_scope.dart';
import 'ui_primitives/menu/menu_scope.dart';
import 'features/manager_suite/application/manager_suite_controller.dart';
import 'features/manager_suite/domain/inventory_ledger.dart';
import 'features/mindful_satiety/application/reflection_controller.dart';
import 'features/mindful_satiety/data/reflection_notifier.dart';
import 'features/mindful_satiety/data/reflection_store.dart';
import 'features/mindful_satiety/presentation/reflection_surfaces.dart';
import 'features/order_home/presentation/order_home_screen.dart';
import 'services/server_menu_availability.dart';
import 'services/shared_preferences_phone_memory.dart';
import 'services/supabase_order_gateway.dart';
import 'services/supabase_order_tracker.dart';
import 'services/supabase_service.dart';
import 'ui_primitives/theme/theme.dart';
import 'ui_primitives/theme/theme_mode_scope.dart';

/// Entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  // Real orders and real stock, even if Supabase failed to start: the gateway
  // then answers "couldn't connect", never a pretend confirmation.
  runApp(
    MawzoonApp(
      orders: SupabaseOrderGateway(),
      availability: ServerMenuAvailability(),
    ),
  );
}

/// The Mawzoon application shell.
///
/// Themes are built once per language rather than per build: a fresh
/// [ThemeData] compares unequal to the last one, and `AnimatedTheme` would
/// then lerp every colour in the tree on every rebuild.
class MawzoonApp extends StatefulWidget {
  /// Creates the app. With no [orders] and [availability] — tests and
  /// previews — it runs on a local demo store and confirms orders locally.
  const MawzoonApp({super.key, this.orders, this.availability});

  /// Where orders go.
  final OrderGateway? orders;

  /// What the menu can sell, from the server. The app owns and disposes it.
  final ServerMenuAvailability? availability;

  @override
  State<MawzoonApp> createState() => _MawzoonAppState();
}

class _MawzoonAppState extends State<MawzoonApp> {
  AppLanguage _language = AppLanguage.arabic;

  /// Follows the phone until the guest picks one with the header toggle.
  ThemeMode _themeMode = ThemeMode.system;
  late ThemeData _light = AppTheme.light(language: _language);
  late ThemeData _dark = AppTheme.dark(language: _language);

  /// Demo only: a local back office, for tests and previews with no server.
  ManagerSuiteController? _demoMenu;

  final SharedPreferencesPhoneMemory _phones = SharedPreferencesPhoneMemory();

  /// Reads and cancels this guest's own orders. Built with the gateway only.
  late final SupabaseOrderTracker _tracker = SupabaseOrderTracker();

  /// Refreshes the menu when the guest comes back to the app, so a dish that
  /// sold out while the phone was in a pocket isn't offered.
  AppLifecycleListener? _lifecycle;

  /// The post-meal loop. Everything it keeps stays on this phone.
  late final ReflectionController _reflections = ReflectionController(
    store: SharedPreferencesReflectionStore(),
    notifier: LocalReflectionNotifier(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_reflections.start());
    final ServerMenuAvailability? availability = widget.availability;
    if (availability == null) {
      _demoMenu = ManagerSuiteController(
        ledger: InventoryLedger.stockedFor(60),
      );
    } else {
      availability.start();
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(availability.refresh()),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    widget.availability?.dispose();
    _demoMenu?.dispose();
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
        themeMode: _themeMode,
        // The scopes wrap the navigator, not the home screen, so routes pushed
        // above home (the checkout sheet) see the same menu and order gateway.
        builder: (BuildContext context, Widget? app) => ThemeModeScope(
          mode: _themeMode,
          onChanged: (ThemeMode m) => setState(() => _themeMode = m),
          child: ListenableBuilder(
            listenable: widget.availability ?? _demoMenu!,
            // One scope above the whole app rather than a lookup per screen.
            // Every screen showing a menu figure reads the same snapshot in
            // the same frame, so two parts of one screen can never disagree
            // about what a dish weighs or whether it can be ordered.
            builder: (BuildContext context, Widget? child) => MenuScope(
              book: _demoMenu?.book ?? RecipeBook.published,
              availability:
                  widget.availability?.value ?? _demoMenu!.availability,
              child: ReflectionScope(
                controller: _reflections,
                child: _withOrders(child!),
              ),
            ),
            child: app,
          ),
        ),
        locale: Locale(_language.code),
        supportedLocales: mawzoonSupportedLocales,
        localizationsDelegates: mawzoonLocalizationsDelegates,
        home: const OrderHomeScreen(),
      );

  Widget _withOrders(Widget child) {
    final OrderGateway? orders = widget.orders;
    if (orders == null) return child;
    return OrderGatewayScope(
      gateway: orders,
      onMenuStale: () => unawaited(widget.availability?.refresh()),
      phoneMemory: _phones,
      tracker: _tracker,
      child: child,
    );
  }
}
