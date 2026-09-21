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

  group('percentage', () {
    test('rounds half away from zero rather than truncating', () {
      // 15% of 33.33 is 4.9995 riyals; truncating would quietly lose a halala
      // on every order.
      expect(const Money(3333).percentage(0.15), const Money(500));
      expect(const Money(100).percentage(0.15), const Money(15));
      expect(const Money(1).percentage(0.5), const Money(1));
    });

    test('zero stays zero', () {
      expect(Money.zero.percentage(0.15), Money.zero);
    });
  });

  group('formatting', () {
    test('always shows two decimal places', () {
      expect(const Money(4900).format(AppLanguage.english), 'SAR 49.00');
      expect(const Money(4905).format(AppLanguage.english), 'SAR 49.05');
      expect(const Money(5).format(AppLanguage.english), 'SAR 0.05');
    });

    test('carries the Arabic currency mark', () {
      expect(const Money(4900).format(AppLanguage.arabic), '49.00 ر.س');
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
