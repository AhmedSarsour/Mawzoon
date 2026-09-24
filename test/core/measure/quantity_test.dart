import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/measure/quantity.dart';

void main() {
  group('construction', () {
    test('a gram is a thousand minor units', () {
      expect(Quantity.grams(1).minorUnits, 1000);
      expect(Quantity.grams(220).minorUnits, 220000);
      expect(Quantity.grams(0.5).minorUnits, 500);
    });

    test('bulk constructors are the same thing, written larger', () {
      expect(Quantity.kilograms(1.5), Quantity.grams(1500));
      expect(Quantity.litres(2), Quantity.millilitres(2000));
    });

    test('a fraction of a piece is representable', () {
      expect(Quantity.pieces(0.25).amount, 0.25);
      expect(Quantity.pieces(0.2).minorUnits, 200);
    });

    test('zero still carries its unit', () {
      expect(Quantity.zeroIn(MeasureUnit.millilitre).isZero, isTrue);
      expect(
        Quantity.zeroIn(MeasureUnit.millilitre),
        isNot(Quantity.zeroIn(MeasureUnit.gram)),
      );
    });

    test('a negative amount is refused rather than clamped', () {
      expect(() => Quantity.grams(-1), throwsArgumentError);
      expect(() => Quantity.millilitres(-0.001), throwsArgumentError);
    });

    test('a number that is not a number is refused', () {
      expect(() => Quantity.grams(double.nan), throwsArgumentError);
      expect(() => Quantity.grams(double.infinity), throwsArgumentError);
    });
  });

  group('arithmetic', () {
    test('adds and subtracts exactly', () {
      expect(Quantity.grams(220) + Quantity.grams(5), Quantity.grams(225));
      expect(Quantity.grams(220) - Quantity.grams(5), Quantity.grams(215));
    });

    test('a store cannot hold less than nothing', () {
      expect(Quantity.grams(5) - Quantity.grams(9), Quantity.grams(0));
      expect((Quantity.grams(5) - Quantity.grams(9)).unit, MeasureUnit.gram);
    });

    test('scales and rounds to the minor unit', () {
      expect(Quantity.grams(220) * 1.6, Quantity.grams(352));
      expect(Quantity.grams(10) * 0.5, Quantity.grams(5));
      expect((Quantity.grams(1) * 0.0001).minorUnits, 0);
    });

    test('a negative factor is refused', () {
      expect(() => Quantity.grams(10) * -1, throwsArgumentError);
    });

    test('grams and millilitres do not combine', () {
      expect(
        () => Quantity.grams(220) + Quantity.millilitres(5),
        throwsArgumentError,
      );
      expect(
        () => Quantity.grams(220) - Quantity.millilitres(5),
        throwsArgumentError,
      );
      expect(
        () => Quantity.grams(220).isAtLeast(Quantity.millilitres(5)),
        throwsArgumentError,
      );
      expect(
        () => Quantity.grams(220).howManyFit(Quantity.pieces(1)),
        throwsArgumentError,
      );
    });

    test('a thousand deductions reconcile exactly', () {
      // The reason the whole type exists. The same loop in floating point
      // drifts; here the remainder is the opening count to the milligram.
      Quantity store = Quantity.kilograms(50);
      const int orders = 1000;
      for (int i = 0; i < orders; i++) {
        store = store - Quantity.grams(37.3);
      }
      expect(store, Quantity.grams(50000 - 37300));
      expect(store.minorUnits, (50000 - 37300) * 1000);
    });

    test('how many portions fit floors, because a part portion is none', () {
      expect(Quantity.grams(1000).howManyFit(Quantity.grams(220)), 4);
      expect(Quantity.grams(880).howManyFit(Quantity.grams(220)), 4);
      expect(Quantity.grams(879).howManyFit(Quantity.grams(220)), 3);
      expect(Quantity.grams(0).howManyFit(Quantity.grams(220)), 0);
    });

    test('dividing by nothing is refused', () {
      expect(
        () => Quantity.grams(100).howManyFit(Quantity.grams(0)),
        throwsArgumentError,
      );
    });

    test('comparison is by amount within a unit', () {
      expect(Quantity.grams(10).isAtLeast(Quantity.grams(10)), isTrue);
      expect(Quantity.grams(10).isAtLeast(Quantity.grams(11)), isFalse);
      expect(
        <Quantity>[Quantity.grams(3), Quantity.grams(1), Quantity.grams(2)]
          ..sort(),
        <Quantity>[Quantity.grams(1), Quantity.grams(2), Quantity.grams(3)],
      );
    });
  });

  group('display', () {
    test('small amounts read in the base unit', () {
      expect(Quantity.grams(220).format(AppLanguage.english), '220 g');
      expect(Quantity.millilitres(5).format(AppLanguage.english), '5 ml');
    });

    test('large amounts switch to bulk rather than counting zeros', () {
      expect(Quantity.grams(12400).format(AppLanguage.english), '12.40 kg');
      expect(Quantity.millilitres(2000).format(AppLanguage.english), '2 L');
    });

    test('the switch happens at the bulk unit, not before', () {
      expect(Quantity.grams(999).format(AppLanguage.english), '999 g');
      expect(Quantity.grams(1000).format(AppLanguage.english), '1 kg');
    });

    test('pieces never go bulk, because there is no bulk piece', () {
      expect(Quantity.pieces(4000).format(AppLanguage.english), '4000 pc');
    });

    test('it reads in Arabic too', () {
      expect(Quantity.grams(220).format(AppLanguage.arabic), '220 جم');
      expect(Quantity.millilitres(5).format(AppLanguage.arabic), '5 مل');
      expect(Quantity.kilograms(3).format(AppLanguage.arabic), '3 كجم');
    });

    test('a fraction keeps one figure rather than fifteen', () {
      expect(Quantity.grams(0.5).format(AppLanguage.english), '0.5 g');
    });
  });

  group('identity', () {
    test('equal amounts in the same unit are equal', () {
      expect(Quantity.grams(220), Quantity.grams(220));
      expect(Quantity.grams(220).hashCode, Quantity.grams(220).hashCode);
    });

    test('the same number in different units is not the same thing', () {
      expect(Quantity.grams(5), isNot(Quantity.millilitres(5)));
    });
  });
}
