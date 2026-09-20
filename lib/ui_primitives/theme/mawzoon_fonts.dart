import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Supplies the two typefaces the app is set in.
///
/// Indirected behind an interface for two reasons. It lets a test build the
/// whole type scale without google_fonts reaching for the network, and it lets
/// a release build swap to fonts bundled in `assets/fonts/` — which is what
/// you want the day the app has to open on a bad connection in a restaurant
/// basement — without touching a single call site.
abstract interface class MawzoonFonts {
  /// Plus Jakarta Sans. Latin copy and every numeric figure.
  TextStyle latin(TextStyle base);

  /// IBM Plex Sans Arabic. All Arabic copy.
  TextStyle arabic(TextStyle base);
}

/// Pulls both faces from Google Fonts, fetching once and caching on device.
final class GoogleMawzoonFonts implements MawzoonFonts {
  /// Creates the default font source.
  const GoogleMawzoonFonts();

  @override
  TextStyle latin(TextStyle base) => GoogleFonts.plusJakartaSans(textStyle: base);

  @override
  TextStyle arabic(TextStyle base) =>
      GoogleFonts.ibmPlexSansArabic(textStyle: base);
}

/// Names the families directly, with no fetching.
///
/// Use this when the `.ttf` files ship in the bundle, and in tests — where a
/// network call would be both slow and a lie about what is being tested.
final class BundledMawzoonFonts implements MawzoonFonts {
  /// Creates a font source that only sets family names.
  const BundledMawzoonFonts({
    this.latinFamily = 'Plus Jakarta Sans',
    this.arabicFamily = 'IBM Plex Sans Arabic',
  });

  /// The family name declared for Latin copy.
  final String latinFamily;

  /// The family name declared for Arabic copy.
  final String arabicFamily;

  @override
  TextStyle latin(TextStyle base) => base.copyWith(
        fontFamily: latinFamily,
        fontFamilyFallback: const <String>['Helvetica Neue', 'Arial'],
      );

  @override
  TextStyle arabic(TextStyle base) => base.copyWith(
        fontFamily: arabicFamily,
        // SF Arabic on iOS and Noto Naskh elsewhere both render harakat
        // correctly; a Latin fallback here would drop the diacritics entirely.
        fontFamilyFallback: const <String>[
          'SF Arabic',
          'Geeza Pro',
          'Noto Naskh Arabic',
          'Noto Sans Arabic',
        ],
      );
}
