/// Bilingual text primitives for the Mawzoon domain layer.
///
/// The `core` layer carries no Flutter dependency, so it cannot reach for
/// `Locale` or `Directionality`. Language is modelled here as a plain Dart
/// enum; the presentation layer maps a `Locale` onto [AppLanguage] once, at
/// the composition root.
library;

/// The two languages Mawzoon ships in.
///
/// Arabic is listed first deliberately: it is the primary language of the
/// restaurant, not an afterthought bolted onto an English original.
enum AppLanguage {
  /// العربية — right-to-left.
  arabic(code: 'ar', isRightToLeft: true),

  /// English — left-to-right.
  english(code: 'en', isRightToLeft: false);

  const AppLanguage({required this.code, required this.isRightToLeft});

  /// IETF/ISO-639-1 language subtag.
  final String code;

  /// Whether text in this language flows right-to-left.
  final bool isRightToLeft;

  /// Resolves a language subtag (`ar`, `ar-SA`, `en`, `en_US`) to a language.
  ///
  /// Falls back to [AppLanguage.arabic] for anything unrecognised, matching
  /// the restaurant's primary audience.
  static AppLanguage fromCode(String? code) {
    if (code == null || code.isEmpty) return AppLanguage.arabic;
    final String primary = code.replaceAll('_', '-').split('-').first.toLowerCase();
    return switch (primary) {
      'en' => AppLanguage.english,
      'ar' => AppLanguage.arabic,
      _ => AppLanguage.arabic,
    };
  }
}

/// An immutable Arabic/English string pair.
///
/// Every user-facing noun in the domain — dish names, segment labels, portion
/// descriptions — is a [LocalizedText] so that no screen can accidentally
/// render a hard-coded English fallback to an Arabic-speaking guest.
final class LocalizedText {
  /// Creates a bilingual string pair. Both languages are mandatory.
  const LocalizedText({required this.ar, required this.en})
      : assert(ar.length > 0, 'Arabic text must not be empty'),
        assert(en.length > 0, 'English text must not be empty');

  /// The Arabic rendering.
  final String ar;

  /// The English rendering.
  final String en;

  /// Returns the string for [language].
  String resolve(AppLanguage language) => switch (language) {
        AppLanguage.arabic => ar,
        AppLanguage.english => en,
      };

  @override
  String toString() => 'LocalizedText(ar: $ar, en: $en)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalizedText && other.ar == ar && other.en == en;

  @override
  int get hashCode => Object.hash(ar, en);
}
