/// Arabic counted-noun agreement for calories.
///
/// Arabic numeral agreement is not "singular vs plural" — it has four forms,
/// and which one a count takes depends on its last two digits, not its
/// absolute size. This is the one counted noun the app currently shows a
/// live, changing number for (`{kcal} سعرة`), so it gets a real function
/// instead of a hand-written string at each call site.
library;

/// The calorie count, agreed with [n] the way an Arabic reader expects.
///
/// - `1` → `سعرة واحدة` (word alone, no digit — Arabic doesn't say "1 سعرة").
/// - `2` → `سعرتان` (the dual form, also word alone).
/// - last two digits of `n` in `3..10` → `$n سعرات` (plural).
/// - everything else (`0`, `11..99`, multiples of 100, …) → `$n سعرة`, the
///   singular used as the default counted form — except `0`, which reads as
///   the bare word with no digit, matching how "زيرو سعرة" would never be said.
String arabicKilocalories(int n) {
  if (n == 1) return 'سعرة واحدة';
  if (n == 2) return 'سعرتان';
  if (n == 0) return 'سعرة';
  final int lastTwoDigits = n % 100;
  final String word =
      lastTwoDigits >= 3 && lastTwoDigits <= 10 ? 'سعرات' : 'سعرة';
  return '$n $word';
}
