import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/ui_primitives/text/mawzoon_text.dart';
import 'package:mawzoon/ui_primitives/theme/theme.dart';

const BundledMawzoonFonts _fonts = BundledMawzoonFonts();

ThemeData _dark({AppLanguage language = AppLanguage.arabic}) =>
    AppTheme.dark(language: language, fonts: _fonts);
ThemeData _light({AppLanguage language = AppLanguage.arabic}) =>
    AppTheme.light(language: language, fonts: _fonts);

Widget _host({
  required ThemeData theme,
  required Widget child,
  TextDirection direction = TextDirection.rtl,
}) =>
    MaterialApp(
      theme: theme,
      locale: const Locale('ar'),
      supportedLocales: mawzoonSupportedLocales,
      localizationsDelegates: mawzoonLocalizationsDelegates,
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('token sets are attached', () {
    for (final MapEntry<String, ThemeData> entry in <String, ThemeData>{
      'dark': _dark(),
      'light': _light(),
    }.entries) {
      test('${entry.key}: all four extensions are present', () {
        final ThemeData theme = entry.value;
        expect(theme.extension<MawzoonColors>(), isNotNull);
        expect(theme.extension<MawzoonTypography>(), isNotNull);
        expect(theme.extension<MawzoonSpacing>(), isNotNull);
        expect(theme.extension<MawzoonElevation>(), isNotNull);
      });
    }

    test('brightness matches the palette in both directions', () {
      expect(_dark().brightness, Brightness.dark);
      expect(_dark().extension<MawzoonColors>()!.brightness, Brightness.dark);
      expect(_light().brightness, Brightness.light);
      expect(_light().extension<MawzoonColors>()!.brightness, Brightness.light);
    });

    test('of() resolves by brightness', () {
      expect(AppTheme.of(Brightness.dark, fonts: _fonts).brightness,
          Brightness.dark,);
      expect(AppTheme.of(Brightness.light, fonts: _fonts).brightness,
          Brightness.light,);
    });
  });

  group('the canvas is the ground everywhere', () {
    test('scaffold and canvas colours both come from the 60% token', () {
      for (final ThemeData theme in <ThemeData>[_dark(), _light()]) {
        final MawzoonColors c = theme.extension<MawzoonColors>()!;
        expect(theme.scaffoldBackgroundColor, c.canvas);
        expect(theme.canvasColor, c.canvas);
        expect(theme.colorScheme.surface, c.canvas);
      }
    });
  });

  // Material's default surface tint lightens a raised surface toward the
  // primary hue. On Smoked Obsidian that is an ember fog over every card.
  group('Material surface tint is suppressed', () {
    test('no component reintroduces the tint', () {
      for (final ThemeData theme in <ThemeData>[_dark(), _light()]) {
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
        expect(theme.dialogTheme.backgroundColor, isNotNull);
        expect(theme.chipTheme.surfaceTintColor, Colors.transparent);
      }
    });

    test('elevation is carried by shadow, not by a raised elevation value', () {
      for (final ThemeData theme in <ThemeData>[_dark(), _light()]) {
        expect(theme.cardTheme.elevation, 0);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.snackBarTheme.elevation, 0);
        expect(theme.extension<MawzoonElevation>()!.platter, isNotEmpty);
      }
    });
  });

  group('typography follows the language', () {
    test('an Arabic theme is set in the Arabic face', () {
      final ThemeData theme = _dark(language: AppLanguage.arabic);
      expect(theme.textTheme.bodyMedium!.fontFamily, _fonts.arabicFamily);
      expect(theme.extension<MawzoonTypography>()!.language,
          AppLanguage.arabic,);
    });

    test('an English theme is set in the Latin face', () {
      final ThemeData theme = _dark(language: AppLanguage.english);
      expect(theme.textTheme.bodyMedium!.fontFamily, _fonts.latinFamily);
    });

    test('text colour is applied across the whole TextTheme', () {
      final ThemeData theme = _dark();
      final MawzoonColors c = theme.extension<MawzoonColors>()!;
      expect(theme.textTheme.bodyMedium!.color, c.ink);
      expect(theme.textTheme.displayLarge!.color, c.ink);
      expect(theme.textTheme.labelSmall!.color, c.ink);
    });
  });

  group('primary action', () {
    testWidgets('renders as an ember pill with a readable label',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          theme: _dark(),
          child: FilledButton(onPressed: () {}, child: const Text('اطلب')),
        ),
      );

      final MawzoonColors c = MawzoonColors.dark();
      final ButtonStyle style =
          tester.widget<FilledButton>(find.byType(FilledButton)).style ??
              _dark().filledButtonTheme.style!;
      expect(
        (_dark().filledButtonTheme.style!.backgroundColor)!
            .resolve(<WidgetState>{}),
        c.ember,
      );
      expect(
        (_dark().filledButtonTheme.style!.foregroundColor)!
            .resolve(<WidgetState>{}),
        c.onEmber,
      );
      expect(style, isNotNull);
    });

    test('meets the 48dp thumb target', () {
      const MawzoonSpacing space = MawzoonSpacing.standard();
      for (final ThemeData theme in <ThemeData>[_dark(), _light()]) {
        final Size min = theme.filledButtonTheme.style!.minimumSize!
            .resolve(<WidgetState>{})!;
        expect(min.height, greaterThanOrEqualTo(space.thumbTarget));
      }
    });

    test('a disabled action recedes rather than shouting', () {
      final MawzoonColors c = MawzoonColors.dark();
      final ButtonStyle style = _dark().filledButtonTheme.style!;
      expect(
        style.backgroundColor!.resolve(<WidgetState>{WidgetState.disabled}),
        c.structure,
      );
      expect(
        style.foregroundColor!.resolve(<WidgetState>{WidgetState.disabled}),
        c.inkFaint,
      );
    });
  });

  group('MawzoonText', () {
    testWidgets('applies the Arabic strut so harakat are never clipped',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          theme: _dark(language: AppLanguage.arabic),
          child: const MawzoonText('صَدْرُ دَجَاجٍ مَشْوِيٌّ'),
        ),
      );

      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.strutStyle, isNotNull);
      expect(text.strutStyle!.forceStrutHeight, isTrue);
      expect(text.strutStyle!.height, MawzoonTypography.arabicBodyHeight);
      expect(text.strutStyle!.leading, MawzoonTypography.arabicStrutLeading);
      expect(text.textHeightBehavior, isNotNull);
    });

    testWidgets('does not force the strut on Latin copy',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _dark(language: AppLanguage.english),
          locale: const Locale('en'),
          supportedLocales: mawzoonSupportedLocales,
          localizationsDelegates: mawzoonLocalizationsDelegates,
          home: const Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(body: MawzoonText('Flame-Seared Chicken')),
          ),
        ),
      );

      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.strutStyle!.forceStrutHeight, isFalse);
    });

    testWidgets('a colour override does not discard the style',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          theme: _dark(),
          child: Builder(
            builder: (BuildContext context) => MawzoonText(
              'موزون',
              style: context.type.sectionTitle,
              color: context.colors.ember,
            ),
          ),
        ),
      );

      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.color, MawzoonColors.dark().ember);
      expect(text.style!.fontSize,
          MawzoonTypography.forLanguage(AppLanguage.arabic, fonts: _fonts)
              .sectionTitle
              .fontSize,);
    });

    testWidgets('renders Arabic without overflowing a tight box',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          theme: _dark(),
          child: const SizedBox(
            width: 140,
            child: MawzoonText('سلطة الشمر والجرجير بالحمضيات'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('context extensions', () {
    testWidgets('read every token set from the ambient theme',
        (WidgetTester tester) async {
      late MawzoonColors colors;
      late MawzoonTypography type;
      late MawzoonSpacing space;
      late MawzoonElevation elevation;
      late bool rtl;
      late AppLanguage language;

      await tester.pumpWidget(
        _host(
          theme: _dark(),
          child: Builder(
            builder: (BuildContext context) {
              colors = context.colors;
              type = context.type;
              space = context.space;
              elevation = context.elevation;
              rtl = context.isRtl;
              language = context.appLanguage;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colors.canvas, MawzoonColors.dark().canvas);
      expect(type.language, AppLanguage.arabic);
      expect(space.screenGutter, 16);
      expect(elevation.platter, isNotEmpty);
      expect(rtl, isTrue);
      expect(language, AppLanguage.arabic);
    });

    testWidgets('fall back in-brand outside the app shell rather than crashing',
        (WidgetTester tester) async {
      late MawzoonSpacing space;
      late MawzoonElevation elevation;

      // A bare ThemeData carries none of the extensions — a widgetbook page or
      // a deep-linked error route. The non-asserting getters must still work.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (BuildContext context) {
              space = context.space;
              elevation = context.elevation;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(space.screenGutter, const MawzoonSpacing.standard().screenGutter);
      expect(elevation.platter, isNotEmpty);
    });
  });

  group('locale plumbing', () {
    test('Arabic is listed first among supported locales', () {
      expect(mawzoonSupportedLocales.first.languageCode, 'ar');
      expect(mawzoonSupportedLocales.map((Locale l) => l.languageCode),
          containsAll(<String>['ar', 'en']),);
    });

    test('appLanguageOf resolves outside a widget tree', () {
      expect(appLanguageOf(const Locale('en', 'US')), AppLanguage.english);
      expect(appLanguageOf(const Locale('ar', 'SA')), AppLanguage.arabic);
      expect(appLanguageOf(null), AppLanguage.arabic);
    });
  });
}
