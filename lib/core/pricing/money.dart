import '../localization/localized_text.dart';

/// An amount of money, held in minor units.
///
/// Integers, never doubles. `0.1 + 0.2` is not `0.3` in binary floating point,
/// and a bill that is off by a halala is a bill a guest is right to dispute.
/// Every arithmetic operation here stays in whole halalas, and the only
/// division rounds explicitly and says which way.
final class Money implements Comparable<Money> {
  /// Creates an amount from whole minor units.
  const Money(this.minorUnits);

  /// Zero.
  static const Money zero = Money(0);

  /// Minor units per major unit: 100 halalas to the riyal.
  static const int minorPerMajor = 100;

  /// The amount, in halalas.
  final int minorUnits;

  /// The amount in riyals, for display only — never for arithmetic.
  double get asMajor => minorUnits / minorPerMajor;

  /// Whether this is exactly zero.
  bool get isZero => minorUnits == 0;

  /// Adds two amounts.
  Money operator +(Money other) => Money(minorUnits + other.minorUnits);

  /// Subtracts an amount.
  Money operator -(Money other) => Money(minorUnits - other.minorUnits);

  /// Multiplies by a whole count, as for a line of several plates.
  Money operator *(int count) => Money(minorUnits * count);

  /// Applies [rate] and rounds half away from zero.
  ///
  /// Used for tax. The rounding is explicit because "it rounds somehow" is how
  /// a ledger ends up a halala short at the end of a busy service.
  Money percentage(double rate) {
    assert(rate >= 0, 'rate must be non-negative');
    return Money((minorUnits * rate).round());
  }

  /// Sums a list, returning [zero] for an empty one.
  static Money sum(Iterable<Money> amounts) =>
      amounts.fold(zero, (Money acc, Money m) => acc + m);

  /// Formats the amount for [language], e.g. `49.00 ر.س` or `SAR 49.00`.
  ///
  /// The figure itself stays in Western digits in both languages, matching
  /// every price tag and receipt a guest in the region actually handles.
  String format(AppLanguage language) {
    final String figure = (minorUnits / minorPerMajor).toStringAsFixed(2);
    return switch (language) {
      AppLanguage.arabic => '$figure ر.س',
      AppLanguage.english => 'SAR $figure',
    };
  }

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  /// Whether this is more than [other].
  bool operator >(Money other) => minorUnits > other.minorUnits;

  /// Whether this is less than [other].
  bool operator <(Money other) => minorUnits < other.minorUnits;

  @override
  String toString() => 'Money(${asMajor.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;
}
