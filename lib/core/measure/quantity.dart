import '../localization/localized_text.dart';

/// How a raw ingredient is counted.
///
/// Three, and there will not be a fourth: everything a kitchen draws from a
/// store is weighed, poured, or counted out.
enum MeasureUnit {
  /// Weighed. Stored in milligrams.
  gram(
    symbol: LocalizedText(ar: 'جم', en: 'g'),
    bulk: LocalizedText(ar: 'كجم', en: 'kg'),
    bulkFactor: 1000,
  ),

  /// Poured. Stored in microlitres.
  millilitre(
    symbol: LocalizedText(ar: 'مل', en: 'ml'),
    bulk: LocalizedText(ar: 'لتر', en: 'L'),
    bulkFactor: 1000,
  ),

  /// Counted out — a lemon, an egg, a flatbread. Stored in thousandths, so
  /// half a lemon is representable and a quarter of one is too.
  piece(
    symbol: LocalizedText(ar: 'حبة', en: 'pc'),
    bulk: LocalizedText(ar: 'حبة', en: 'pc'),
    bulkFactor: 1,
  );

  const MeasureUnit({
    required this.symbol,
    required this.bulk,
    required this.bulkFactor,
  });

  /// How a small amount is written.
  final LocalizedText symbol;

  /// How a large amount is written.
  final LocalizedText bulk;

  /// How many of [symbol] make one [bulk].
  final int bulkFactor;
}

/// An amount of something, in one unit, held as an integer.
///
/// ## Why integers
///
/// Inventory is the same problem as money. A deduction engine subtracts a few
/// hundred grams from a store several hundred times a service, every service,
/// and a `double` accumulates a little error on every one of those
/// subtractions. The error is invisible for a week and then the count of
/// chicken in the system is 40g away from the count on the shelf and nobody
/// can say why. Minor units — milligrams, microlitres, thousandths of an item
/// — make every deduction exact and every total reproducible.
///
/// Adding grams to millilitres throws rather than coercing. 220g of potato and
/// 5ml of oil are not 225 of anything, and the moment a codebase lets them be,
/// a purchase order is wrong.
final class Quantity implements Comparable<Quantity> {
  const Quantity._(this.minorUnits, this.unit);

  /// A mass in grams. Fractions are kept to the milligram.
  factory Quantity.grams(num amount) => Quantity._(
        _toMinor(amount, 'grams'),
        MeasureUnit.gram,
      );

  /// A volume in millilitres. Fractions are kept to the microlitre.
  factory Quantity.millilitres(num amount) => Quantity._(
        _toMinor(amount, 'millilitres'),
        MeasureUnit.millilitre,
      );

  /// A count of whole or part items.
  factory Quantity.pieces(num amount) => Quantity._(
        _toMinor(amount, 'pieces'),
        MeasureUnit.piece,
      );

  /// A mass in kilograms, for a delivery note rather than a recipe line.
  factory Quantity.kilograms(num amount) => Quantity.grams(amount * 1000);

  /// A volume in litres.
  factory Quantity.litres(num amount) => Quantity.millilitres(amount * 1000);

  /// Nothing, in [unit]. Units still matter at zero: an empty tub of oil is
  /// not an empty tray of potatoes, and adding them must still throw.
  factory Quantity.zeroIn(MeasureUnit unit) => Quantity._(0, unit);

  static int _toMinor(num amount, String what) {
    if (amount.isNaN || amount.isInfinite) {
      throw ArgumentError.value(amount, what, 'must be a finite number');
    }
    if (amount < 0) {
      throw ArgumentError.value(amount, what, 'must not be negative');
    }
    return (amount * 1000).round();
  }

  /// The amount, in thousandths of [unit].
  final int minorUnits;

  /// What is being counted, and how.
  final MeasureUnit unit;

  /// The amount as a decimal of [unit], for display and for ratios.
  double get amount => minorUnits / 1000;

  /// Whether there is none of it.
  bool get isZero => minorUnits == 0;

  /// The sum, which must be of the same unit.
  Quantity operator +(Quantity other) =>
      Quantity._(minorUnits + _sameUnit(other, '+'), unit);

  /// The difference, floored at zero.
  ///
  /// A store cannot hold less than nothing. An over-draw is a real event — the
  /// line used more than the book says was there — but it is reported by
  /// [InventoryLedger], not encoded as a negative amount that then quietly
  /// makes the next reorder calculation wrong.
  Quantity operator -(Quantity other) {
    final int next = minorUnits - _sameUnit(other, '-');
    return Quantity._(next < 0 ? 0 : next, unit);
  }

  /// Scaled by a factor, rounded to the minor unit.
  Quantity operator *(num factor) {
    if (factor < 0) {
      throw ArgumentError.value(factor, 'factor', 'must not be negative');
    }
    return Quantity._((minorUnits * factor).round(), unit);
  }

  /// How many times [other] fits into this, as a whole number.
  ///
  /// The question inventory actually asks: how many more portions can the line
  /// make? A part portion is not a portion, so this floors.
  int howManyFit(Quantity other) {
    final int divisor = _sameUnit(other, 'howManyFit');
    if (divisor <= 0) {
      throw ArgumentError.value(other, 'other', 'must be greater than zero');
    }
    return minorUnits ~/ divisor;
  }

  /// Whether this is at least [other].
  bool isAtLeast(Quantity other) => minorUnits >= _sameUnit(other, 'isAtLeast');

  int _sameUnit(Quantity other, String op) {
    if (other.unit != unit) {
      throw ArgumentError(
        'cannot $op ${other.unit.name} and ${unit.name}: '
        'a quantity only combines with its own unit',
      );
    }
    return other.minorUnits;
  }

  /// How the amount reads on a manager's screen.
  ///
  /// Switches to the bulk unit past a thousand, because "12400 g" is a number
  /// someone has to decode and "12.4 kg" is one they can read.
  String format(AppLanguage language) {
    final bool useBulk =
        unit.bulkFactor > 1 && minorUnits >= unit.bulkFactor * 1000;
    final double shown = useBulk ? amount / unit.bulkFactor : amount;
    final LocalizedText label = useBulk ? unit.bulk : unit.symbol;
    final String digits = shown == shown.roundToDouble()
        ? shown.round().toString()
        : shown.toStringAsFixed(useBulk ? 2 : 1);
    return '$digits ${label.resolve(language)}';
  }

  @override
  int compareTo(Quantity other) =>
      minorUnits.compareTo(_sameUnit(other, 'compareTo'));

  @override
  String toString() => '$amount${unit.symbol.en}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Quantity && other.minorUnits == minorUnits && other.unit == unit;

  @override
  int get hashCode => Object.hash(minorUnits, unit);
}
