import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/portion_scale.dart';

/// The kinds of thing the loop can learn. Dismissal is per kind.
enum InsightKind {
  /// The portion is consistently too much or too little.
  portion,

  /// Quick-release carbs line up with sluggish afternoons.
  carbRelease,
}

/// Something the guest's own answers suggest. Never a number, never a score.
sealed class SatietyInsight {
  const SatietyInsight();

  /// Which kind, for dismissal.
  InsightKind get kind;

  /// The sentence shown under the portion toggle.
  LocalizedText get message;
}

/// "This portion has been more / less than you want. Try the other one?"
final class PortionInsight extends SatietyInsight {
  /// Creates a portion insight.
  const PortionInsight({required this.from, required this.suggested});

  /// The portion the answers were about.
  final PortionScale from;

  /// The portion to try instead.
  final PortionScale suggested;

  @override
  InsightKind get kind => InsightKind.portion;

  /// Whether the answers said "too much" (rather than "too little").
  bool get wasTooMuch => suggested == PortionScale.standardBalance;

  @override
  LocalizedText get message => wasTooMuch
      ? LocalizedText(
          ar: 'آخر أطباقك في «${from.label.ar}» كانت أثقل مما تحتاج.',
          en: 'Your recent ${from.label.en} plates felt heavier than you need.',
        )
      : LocalizedText(
          ar: 'آخر أطباقك في «${from.label.ar}» كانت أخفّ مما تحتاج.',
          en: 'Your recent ${from.label.en} plates felt lighter than you need.',
        );

  /// The one-tap action.
  LocalizedText get action => LocalizedText(
        ar: 'جرّب ${suggested.label.ar}',
        en: 'Try ${suggested.label.en}',
      );
}

/// "Your energy holds steadier with slow-release carbs."
final class CarbReleaseInsight extends SatietyInsight {
  /// Creates the insight.
  const CarbReleaseInsight();

  @override
  InsightKind get kind => InsightKind.carbRelease;

  @override
  LocalizedText get message => const LocalizedText(
        ar: 'طاقتك أثبت مع الكربوهيدرات بطيئة الإطلاق.',
        en: 'Your energy holds steadier with slow-release carbs.',
      );
}
