import '../../../core/nutrition/glycemic.dart';
import '../../../core/nutrition/portion_scale.dart';
import 'reflection_journal.dart';
import 'satiety_answer.dart';
import 'satiety_insight.dart';

/// Turns the guest's answers into at most a couple of gentle suggestions.
///
/// Algorithm: windowed majority vote. One pass over a journal of at most
/// [ReflectionJournal.capacity] entries, so O(n) time and O(1) space per
/// bucket. Chosen over anything statistical because it needs no training data,
/// works from the third answer, and every suggestion can be explained in one
/// sentence. Fractions are compared in integers (3k ≥ 2n) so "exactly 2/3"
/// can't fall on the wrong side of a rounding error.
abstract final class SatietyCorrelation {
  /// How many recent answers on one portion the portion rule reads.
  static const int portionWindow = 6;

  /// How many recent answers the carb rule reads.
  static const int carbWindow = 12;

  /// Fewest answers any rule will speak from.
  static const int minimumVotes = 3;

  /// Fewest non-quick answers needed to show the contrast.
  static const int minimumContrast = 2;

  /// New answers needed before a dismissed kind can come back.
  static const int answersToResurface = 5;

  /// Suggestions for the plate on screen, most useful first.
  ///
  /// [currentScale] is the portion toggle's value: the portion rule only reads
  /// answers about that portion. [currentBalance] is the current plate's carb
  /// release; the carb rule only speaks when that is `quick`, i.e. when the
  /// suggestion is about the plate the guest is actually looking at.
  static List<SatietyInsight> insightsFor(
    ReflectionRecord record, {
    required PortionScale currentScale,
    GlycemicBalance? currentBalance,
  }) {
    final List<MealReflection> entries = record.journal.entries;
    final PortionInsight? portion = _suppressed(record, InsightKind.portion)
        ? null
        : _portion(entries, currentScale);
    return <SatietyInsight>[
      if (portion != null) portion,
      if (!_suppressed(record, InsightKind.carbRelease) &&
          currentBalance == GlycemicBalance.quick &&
          _carbReleaseHolds(entries))
        const CarbReleaseInsight(),
    ];
  }

  static bool _suppressed(ReflectionRecord record, InsightKind kind) {
    final int? at = record.dismissedAt[kind];
    return at != null && record.totalAnswered - at < answersToResurface;
  }

  static bool _atLeastTwoThirds(int count, int of) => 3 * count >= 2 * of;

  static bool _atMostOneThird(int count, int of) => 3 * count <= of;

  static PortionInsight? _portion(
    List<MealReflection> entries,
    PortionScale scale,
  ) {
    int n = 0;
    int light = 0;
    int heavy = 0;
    for (final MealReflection r in entries) {
      if (r.snapshot.scale != scale) continue;
      n++;
      if (r.satiety == SatietyLevel.light) light++;
      if (r.satiety == SatietyLevel.heavy) heavy++;
      if (n == portionWindow) break;
    }
    if (n < minimumVotes) return null;

    // Only suggest a portion that exists: there is nothing smaller than
    // standard and nothing larger than athletic.
    return switch (scale) {
      PortionScale.athleticLoad when _atLeastTwoThirds(heavy, n) =>
        const PortionInsight(
          from: PortionScale.athleticLoad,
          suggested: PortionScale.standardBalance,
        ),
      PortionScale.standardBalance when _atLeastTwoThirds(light, n) =>
        const PortionInsight(
          from: PortionScale.standardBalance,
          suggested: PortionScale.athleticLoad,
        ),
      _ => null,
    };
  }

  /// Sluggish after quick-release plates, and *not* sluggish after the
  /// others. Without the contrast, sluggish everywhere means a hard week,
  /// not a carb.
  static bool _carbReleaseHolds(List<MealReflection> entries) {
    int quick = 0;
    int quickSluggish = 0;
    int other = 0;
    int otherSluggish = 0;
    for (final MealReflection r in entries.take(carbWindow)) {
      final bool sluggish = r.energy == EnergyLevel.sluggish;
      if (r.snapshot.glycemicBalance == GlycemicBalance.quick) {
        quick++;
        if (sluggish) quickSluggish++;
      } else {
        other++;
        if (sluggish) otherSluggish++;
      }
    }
    return quick >= minimumVotes &&
        _atLeastTwoThirds(quickSluggish, quick) &&
        other >= minimumContrast &&
        _atMostOneThird(otherSluggish, other);
  }
}
