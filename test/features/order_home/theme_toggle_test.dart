import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/features/order_home/presentation/order_home_screen.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';
import 'package:mawzoon/ui_primitives/theme/theme_mode_scope.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

Widget _app({ThemeMode mode = ThemeMode.light, ValueChanged<ThemeMode>? on}) =>
    MaterialApp(
      theme: AppTheme.light(language: AppLanguage.arabic, fonts: _fonts),
      darkTheme: AppTheme.dark(language: AppLanguage.arabic, fonts: _fonts),
      themeMode: mode,
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      builder: (BuildContext context, Widget? app) => on == null
          ? app!
          : ThemeModeScope(mode: mode, onChanged: on, child: app!),
      home: const OrderHomeScreen(),
    );

void main() {
  testWidgets('the header toggle asks the app for dark mode from light',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ThemeMode? asked;
    await tester.pumpWidget(_app(on: (ThemeMode m) => asked = m));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    expect(asked, ThemeMode.dark);
  });

  testWidgets('no scope, no toggle (tests and the workbench stay clean)',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
    expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
  });
}
