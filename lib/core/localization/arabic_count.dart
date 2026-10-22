/// Arabic counted-noun agreement.
///
/// Arabic numeral agreement is not "singular vs plural" — it has four forms,
/// and which one a count takes depends on its last two digits, not its
/// absolute size. Every live, changing count on a screen goes through
/// [arabicCounted] rather than a hand-written string at the call site.
library;

/// [n] agreed with its noun:
/// - `1` → [one] alone (Arabic doesn't say "1 سعرة"), `2` → [two] alone (dual);
/// - last two digits in `3..10` → `$n [few]` (plural);
/// - everything else → `$n [many]` (singular as the counted form), except `0`,
///   which reads as the bare [many].
String arabicCounted(
  int n, {
  required String one,
  required String two,
  required String few,
  required String many,
}) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n == 0) return many;
  final int lastTwoDigits = n % 100;
  return lastTwoDigits >= 3 && lastTwoDigits <= 10 ? '$n $few' : '$n $many';
}

/// The calorie count: `سعرة واحدة`, `سعرتان`, `5 سعرات`, `550 سعرة`.
String arabicKilocalories(int n) => arabicCounted(
      n,
      one: 'سعرة واحدة',
      two: 'سعرتان',
      few: 'سعرات',
      many: 'سعرة',
    );

/// Stock items, in the genitive it takes after a noun (`احفظ جرد …`):
/// `مادة واحدة`, `مادتين`, `8 مواد`, `23 مادة`.
String arabicItemsGenitive(int n) => arabicCounted(
      n,
      one: 'مادة واحدة',
      two: 'مادتين',
      few: 'مواد',
      many: 'مادة',
    );
