import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/localization/localized_text.dart';
import 'mawzoon_colors.dart';
import 'mawzoon_elevation.dart';
import 'mawzoon_spacing.dart';
import 'mawzoon_typography.dart';

/// Ergonomic access to the Mawzoon token sets.
///
/// `context.colors.ember` instead of
/// `Theme.of(context).extension<MawzoonColors>()!.ember`. The verbose form is
/// exactly what pushes people to paste a hex literal instead, so the short
/// form is part of keeping the palette honest.
///
/// Each getter falls back to the token set matching the ambient brightness or
/// locale rather than throwing on a missing extension. A screen shown outside
/// the app shell — a widgetbook page, a golden test, a deep-linked error
/// route — then renders in-brand instead of crashing, while an assertion still
/// names the mistake in debug.
extension MawzoonThemeContext on BuildContext {
  /// The role-based palette.
  MawzoonColors get colors {
    final ThemeData theme = Theme.of(this);
    final MawzoonColors? found = theme.extension<MawzoonColors>();
    assert(
      found != null,
      'MawzoonColors is missing from the theme. Build ThemeData with '
      'AppTheme.dark() or AppTheme.light() rather than ThemeData() directly.',
    );
    return found ?? MawzoonColors.of(theme.brightness);
  }

  /// The bilingual type scale.
  MawzoonTypography get type {
    final MawzoonTypography? found =
        Theme.of(this).extension<MawzoonTypography>();
    assert(
      found != null,
      'MawzoonTypography is missing from the theme. Build ThemeData with '
      'AppTheme.dark() or AppTheme.light() rather than ThemeData() directly.',
    );
    return found ?? MawzoonTypography.forLanguage(appLanguage);
  }

  /// The spacing and radius scale.
  MawzoonSpacing get space =>
      Theme.of(this).extension<MawzoonSpacing>() ??
      const MawzoonSpacing.standard();

  /// The shadow ladder.
  MawzoonElevation get elevation {
    final ThemeData theme = Theme.of(this);
    return theme.extension<MawzoonElevation>() ??
        MawzoonElevation.of(theme.brightness);
  }

  /// The domain language behind the ambient [Locale].
  ///
  /// The mapping lives here rather than in `core/`, because `core/` is pure
  /// Dart and must never see a Flutter [Locale].
  AppLanguage get appLanguage =>
      AppLanguage.fromCode(Localizations.maybeLocaleOf(this)?.languageCode);

  /// Whether the current layout flows right-to-left.
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}

/// Maps a [Locale] to the domain's [AppLanguage] outside a widget tree.
///
/// For a `MaterialApp.localeResolutionCallback` or a router redirect, where
/// there is no [BuildContext] to read from yet.
AppLanguage appLanguageOf(Locale? locale) =>
    AppLanguage.fromCode(locale?.languageCode);

/// The locales Mawzoon ships, Arabic first.
const List<Locale> mawzoonSupportedLocales = <Locale>[
  Locale('ar'),
  Locale('en'),
];

/// The delegates a Mawzoon [MaterialApp] must install.
///
/// Flutter's built-in localizations cover English only. Without the global
/// delegates an Arabic locale falls back to English for every framework
/// string — the date picker, the text-selection menu, the "Back" tooltip —
/// and, worse, Material's own widgets stop resolving right-to-left defaults.
/// Bidirectional support is not just a [Directionality] wrapper.
const List<LocalizationsDelegate<dynamic>> mawzoonLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
