import '../../../core/localization/localized_text.dart';

/// How full the guest felt after the meal.
///
/// Three points, not five: the middle of a five-point scale is where people
/// park when they don't want to think, and the extremes mean nothing.
enum SatietyLevel {
  /// Could have eaten more.
  light(label: LocalizedText(ar: 'خفيف', en: 'Light')),

  /// Right where they wanted to be.
  balanced(label: LocalizedText(ar: 'متوازن تماماً', en: 'Perfectly Balanced')),

  /// More than they wanted.
  heavy(label: LocalizedText(ar: 'ممتلئ جداً', en: 'Heavily Satiated'));

  const SatietyLevel({required this.label});

  /// What the chip says.
  final LocalizedText label;
}

/// How the guest's energy felt after the meal.
enum EnergyLevel {
  /// Settled, even.
  calm(label: LocalizedText(ar: 'هادئ', en: 'Calm')),

  /// Lifted.
  energized(label: LocalizedText(ar: 'نشيط', en: 'Energized')),

  /// Heavy, slow.
  sluggish(label: LocalizedText(ar: 'خامل', en: 'Sluggish'));

  const EnergyLevel({required this.label});

  /// What the chip says.
  final LocalizedText label;
}
