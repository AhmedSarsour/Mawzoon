import '../localization/localized_text.dart';
import '../menu/dietary_metadata.dart';
import '../menu/ingredient_option.dart';
import '../menu/plate_segment.dart';

/// A guest's standing dietary preferences.
///
/// [avoidedAllergens] is a safety contract and is enforced hard: a plate
/// carrying one is reported as [PlateAdvisorySeverity.blocking]. [preferredTags]
/// is a soft preference and only ever produces a gentle note.
final class GuestDietaryProfile {
  /// Creates a dietary profile.
  const GuestDietaryProfile({
    this.avoidedAllergens = const <Allergen>{},
    this.preferredTags = const <DietaryTag>{},
  });

  /// A guest with nothing declared.
  static const GuestDietaryProfile unrestricted = GuestDietaryProfile();

  /// Allergens the guest must not be served.
  final Set<Allergen> avoidedAllergens;

  /// Dietary properties the guest prefers their whole plate to satisfy.
  final Set<DietaryTag> preferredTags;

  /// Whether this profile declares anything at all.
  bool get isUnrestricted =>
      avoidedAllergens.isEmpty && preferredTags.isEmpty;
}

/// How seriously to treat an advisory.
enum PlateAdvisorySeverity {
  /// The guest cannot be served this plate as configured.
  blocking,

  /// Worth surfacing, but the guest decides.
  informational,
}

/// Something worth telling the guest about their plate.
///
/// Never called an "error". The Plate Architect does not refuse to draw an
/// unbalanced or unusual plate — it draws it faithfully and annotates it. The
/// single exception is a declared allergen, which is a safety matter.
final class PlateAdvisory {
  /// Creates an advisory.
  const PlateAdvisory({
    required this.severity,
    required this.message,
    this.segment,
    this.allergen,
  });

  /// How seriously to treat this advisory.
  final PlateAdvisorySeverity severity;

  /// What to tell the guest.
  final LocalizedText message;

  /// The compartment responsible, when one is.
  final PlateSegment? segment;

  /// The allergen responsible, for a safety advisory.
  final Allergen? allergen;

  /// Whether this advisory prevents checkout.
  bool get isBlocking => severity == PlateAdvisorySeverity.blocking;

  @override
  String toString() => 'PlateAdvisory(${severity.name}: ${message.en})';
}

/// Screens a set of chosen components against a guest's declared profile.
///
/// Pure and synchronous; takes components rather than a state object so it can
/// also vet a curated signature plate before it is ever shown.
abstract final class PlateValidator {
  /// Returns every advisory raised by [components] for [profile].
  ///
  /// An empty list means the plate is safe and matches the guest's stated
  /// preferences. Advisories are ordered blocking-first so a UI can render the
  /// list top-down without sorting.
  static List<PlateAdvisory> validate({
    required Iterable<IngredientOption> components,
    GuestDietaryProfile profile = GuestDietaryProfile.unrestricted,
  }) {
    final List<PlateAdvisory> blocking = <PlateAdvisory>[];
    final List<PlateAdvisory> informational = <PlateAdvisory>[];
    final List<IngredientOption> chosen = components.toList(growable: false);

    for (final IngredientOption option in chosen) {
      for (final Allergen allergen in option.allergens) {
        if (!profile.avoidedAllergens.contains(allergen)) continue;
        blocking.add(
          PlateAdvisory(
            severity: PlateAdvisorySeverity.blocking,
            segment: option.segment,
            allergen: allergen,
            message: LocalizedText(
              ar: '${option.name.ar} يحتوي على ${allergen.label.ar}. '
                  'اختر بديلًا من نفس القسم.',
              en: '${option.name.en} contains ${allergen.label.en}. '
                  'Pick another option in this compartment.',
            ),
          ),
        );
      }
    }

    for (final DietaryTag tag in profile.preferredTags) {
      final List<IngredientOption> offenders = chosen
          .where((IngredientOption o) => !o.dietaryTags.contains(tag))
          .toList(growable: false);
      if (offenders.isEmpty) continue;
      final String namesAr =
          offenders.map((IngredientOption o) => o.name.ar).join('، ');
      final String namesEn =
          offenders.map((IngredientOption o) => o.name.en).join(', ');
      informational.add(
        PlateAdvisory(
          severity: PlateAdvisorySeverity.informational,
          segment: offenders.first.segment,
          message: LocalizedText(
            ar: 'هذا الطبق ليس ${tag.label.ar} بالكامل بسبب: $namesAr.',
            en: 'This plate is not fully ${tag.label.en} because of: $namesEn.',
          ),
        ),
      );
    }

    return <PlateAdvisory>[...blocking, ...informational];
  }

  /// Whether [components] are safe to serve to [profile].
  static bool isServable({
    required Iterable<IngredientOption> components,
    GuestDietaryProfile profile = GuestDietaryProfile.unrestricted,
  }) =>
      !validate(components: components, profile: profile)
          .any((PlateAdvisory a) => a.isBlocking);
}
