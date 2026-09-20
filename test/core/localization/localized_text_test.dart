import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';

void main() {
  group('AppLanguage', () {
    test('knows its own text direction', () {
      expect(AppLanguage.arabic.isRightToLeft, isTrue);
      expect(AppLanguage.english.isRightToLeft, isFalse);
    });

    test('parses subtags, regions and underscore forms', () {
      expect(AppLanguage.fromCode('ar'), AppLanguage.arabic);
      expect(AppLanguage.fromCode('ar-SA'), AppLanguage.arabic);
      expect(AppLanguage.fromCode('ar_EG'), AppLanguage.arabic);
      expect(AppLanguage.fromCode('en'), AppLanguage.english);
      expect(AppLanguage.fromCode('en-GB'), AppLanguage.english);
      expect(AppLanguage.fromCode('EN'), AppLanguage.english);
    });

    test('falls back to Arabic, the restaurant\'s primary language', () {
      expect(AppLanguage.fromCode(null), AppLanguage.arabic);
      expect(AppLanguage.fromCode(''), AppLanguage.arabic);
      expect(AppLanguage.fromCode('fr'), AppLanguage.arabic);
    });
  });

  group('LocalizedText', () {
    const LocalizedText text = LocalizedText(ar: 'موزون', en: 'Mawzoon');

    test('resolves per language', () {
      expect(text.resolve(AppLanguage.arabic), 'موزون');
      expect(text.resolve(AppLanguage.english), 'Mawzoon');
    });

    test('is a value type', () {
      expect(text, const LocalizedText(ar: 'موزون', en: 'Mawzoon'));
      expect(text.hashCode, const LocalizedText(ar: 'موزون', en: 'Mawzoon').hashCode);
      expect(text, isNot(const LocalizedText(ar: 'موزون', en: 'Balanced')));
    });

    test('refuses an empty rendering in either language', () {
      expect(() => LocalizedText(ar: '', en: 'x'), throwsA(isA<AssertionError>()));
      expect(() => LocalizedText(ar: 'س', en: ''), throwsA(isA<AssertionError>()));
    });
  });
}
