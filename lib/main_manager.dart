import 'package:flutter/material.dart';

import 'core/localization/localized_text.dart';
import 'features/manager_suite/application/manager_suite_controller.dart';
import 'features/manager_suite/domain/inventory_ledger.dart';
import 'features/manager_suite/presentation/manager_shell.dart';
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
void main() => runApp(const MawzoonManagerApp());

/// The manager application shell.
class MawzoonManagerApp extends StatefulWidget {
  /// Creates the manager app.
  const MawzoonManagerApp({
    super.key,
    this.language = AppLanguage.arabic,
    this.signedInAs = 'manager',
  });

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

  /// The suite outlives any screen showing it.
  ///
  /// The seam a real install replaces: the opening count comes from the last
  /// stock take, and calibrations from wherever they were last saved. Here it
  /// starts from a full store so the office is inspectable before either
  /// exists.
  late final ManagerSuiteController _suite = ManagerSuiteController(
    ledger: InventoryLedger.stockedFor(60),
    signedInAs: widget.signedInAs,
  );

  @override
  void dispose() {
    _suite.dispose();
    super.dispose();
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
        home: ManagerShell(controller: _suite),
      );
}
