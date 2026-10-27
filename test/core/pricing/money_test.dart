import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/pricing/money.dart';

void main() {
  group('Money is exact', () {
    test('holds whole minor units', () {
      expect(const Money(4900).minorUnits, 4900);
      expect(const Money(4900).asMajor, 49.0);
      expect(Money.zero.isZero, isTrue);
    });

    // The reason this type exists at all.
    test('adds without the floating-point drift a double would introduce', () {
      const Money tenHalalas = Money(10);
      const Money twentyHalalas = Money(20);
      expect((tenHalalas + twentyHalalas).minorUnits, 30);

      // The same sum in riyals as doubles does not land on 0.30.
      expect(0.1 + 0.2 == 0.3, isFalse);
      expect((tenHalalas + twentyHalalas).asMajor, 0.3);
    });

    test('a hundred additions of one halala is exactly one riyal', () {
      Money running = Money.zero;
      for (int i = 0; i < 100; i++) {
        running += const Money(1);
      }
      expect(running, const Money(100));
      expect(running.asMajor, 1.0);
    });

    test('subtracts and multiplies', () {
      expect(const Money(5000) - const Money(1200), const Money(3800));
      expect(const Money(4900) * 3, const Money(14700));
    });

    test('sums a list, and an empty one is zero', () {
      expect(Money.sum(const <Money>[]), Money.zero);
      expect(
        Money.sum(const <Money>[Money(4900), Money(800), Money(1200)]),
        const Money(6900),
      );
    });
  });

  group('includedTax', () {
    test('extracts 18% from a VAT-inclusive price', () {
      // 49.00 ₪ holds 49 * 18 / 118 = 7.4746 ₪ of VAT.
      expect(const Money(4900).includedTax(1800), const Money(747));
      expect(const Money(6100).includedTax(1800), const Money(931));
    });

    test('rounds an exact half away from zero', () {
      // At 100%, 0.01 holds 0.005 and 0.03 holds 0.015.
      expect(const Money(1).includedTax(10000), const Money(1));
      expect(const Money(3).includedTax(10000), const Money(2));
    });

    test('matches remainder rounding for every amount up to 200 ₪', () {
      for (final int bp in <int>[0, 1700, 1800, 10000]) {
        for (int m = 0; m <= 20000; m++) {
          final int gross = 10000 + bp;
          final int q = (m * bp) ~/ gross;
          final int r = (m * bp) % gross;
          final int expected = 2 * r >= gross ? q + 1 : q;
          expect(Money(m).includedTax(bp).minorUnits, expected,
              reason: '$m at $bp',);
        }
      }
    });

    test('zero VAT (exempt dealer) is zero', () {
      expect(const Money(4900).includedTax(0), Money.zero);
    });
  });

  group('formatting', () {
    test('always shows two decimal places', () {
      expect(const Money(4900).format(AppLanguage.english), '₪49.00');
      expect(const Money(4905).format(AppLanguage.english), '₪49.05');
      expect(const Money(5).format(AppLanguage.english), '₪0.05');
    });

    test('carries the Arabic currency mark', () {
      expect(const Money(4900).format(AppLanguage.arabic), '49.00 ₪');
    });

    test('keeps Western digits in both languages', () {
      // Matching every price tag and receipt a guest in the region handles.
      expect(const Money(4900).format(AppLanguage.arabic), contains('49.00'));
    });
  });

  group('comparison', () {
    test('orders by amount', () {
      expect(const Money(100) > const Money(50), isTrue);
      expect(const Money(50) < const Money(100), isTrue);
      expect(const Money(100).compareTo(const Money(100)), 0);
      final List<Money> sorted = <Money>[
        const Money(300),
        const Money(100),
        const Money(200),
      ]..sort();
      expect(sorted, const <Money>[Money(100), Money(200), Money(300)]);
    });

    test('is a value type', () {
      expect(const Money(4900), const Money(4900));
      expect(const Money(4900).hashCode, const Money(4900).hashCode);
      expect(const Money(4900), isNot(const Money(4901)));
    });
  });
}
