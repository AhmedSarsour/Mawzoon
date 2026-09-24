import '../localization/localized_text.dart';
import 'ingredient_option.dart';
import '../nutrition/macro_profile.dart';

/// How serious a finding against a proposed calibration is.
enum CalibrationSeverity {
  /// Cannot be committed. The numbers describe a food that cannot exist, or
  /// would crash something downstream.
  blocking(label: LocalizedText(ar: 'يمنع الحفظ', en: 'Blocks saving')),

  /// Can be committed, but a manager should look again.
  advisory(label: LocalizedText(ar: 'للمراجعة', en: 'Worth a look'));

  const CalibrationSeverity({required this.label});

  /// How it reads on the form.
  final LocalizedText label;
}

/// Something wrong, or suspicious, about a proposed calibration.
final class CalibrationFinding {
  /// Creates a finding.
  const CalibrationFinding({
    required this.severity,
    required this.field,
    required this.message,
  });

  /// Blocking or advisory.
  final CalibrationSeverity severity;

  /// Which number it is about, so the form can point at it.
  final CalibrationField field;

  /// What is wrong, in both languages, aimed at a manager rather than a
  /// developer.
  final LocalizedText message;

  /// Whether this stops the calibration being saved.
  bool get isBlocking => severity == CalibrationSeverity.blocking;

  @override
  String toString() => '${severity.name}:${field.name}';
}

/// The editable numbers on the calibrator form.
enum CalibrationField {
  /// Cooked mass of the standard portion.
  portionGrams(label: LocalizedText(ar: 'وزن الحصة', en: 'Portion weight')),

  /// Grams of protein.
  protein(label: LocalizedText(ar: 'بروتين', en: 'Protein')),

  /// Grams of total carbohydrate.
  carbohydrate(label: LocalizedText(ar: 'كربوهيدرات', en: 'Carbohydrate')),

  /// Grams of fat.
  fat(label: LocalizedText(ar: 'دهون', en: 'Fat')),

  /// Grams of dietary fibre.
  fibre(label: LocalizedText(ar: 'ألياف', en: 'Fibre')),

  /// Milligrams of sodium.
  sodium(label: LocalizedText(ar: 'صوديوم', en: 'Sodium'));

  const CalibrationField({required this.label});

  /// The field's name on the form.
  final LocalizedText label;

  /// Whether the field is a mass in grams, as opposed to milligrams.
  bool get isGrams => this != CalibrationField.sodium;
}

/// A calibration a manager is still editing.
///
/// ## Why a draft exists at all
///
/// The obvious design puts the manager's numbers straight into a
/// [MacroProfile]. That design crashes. [MacroProfile] asserts that fibre
/// cannot exceed the carbohydrate it is a subset of, so a manager who types
/// the fibre before correcting the carbohydrate takes the app down in debug
/// and publishes a nonsense panel in release. A draft holds loose numbers that
/// are allowed to be wrong mid-edit, and only [commit] — which cannot be
/// reached while a blocking finding stands — produces the real thing.
final class CalibrationDraft {
  /// Creates a draft.
  const CalibrationDraft({
    required this.componentId,
    required this.portionGrams,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    required this.dietaryFiberGrams,
    required this.sodiumMilligrams,
    this.note,
  });

  /// A draft seeded with what the component currently publishes.
  ///
  /// The form opens on the truth. A manager adjusting for batch variance is
  /// nudging a number they can see, not re-entering a panel from memory.
  factory CalibrationDraft.from(IngredientOption option) => CalibrationDraft(
        componentId: option.id,
        portionGrams: option.basePortionGrams,
        proteinGrams: option.baseMacros.proteinGrams,
        carbohydrateGrams: option.baseMacros.carbohydrateGrams,
        fatGrams: option.baseMacros.fatGrams,
        dietaryFiberGrams: option.baseMacros.dietaryFiberGrams,
        sodiumMilligrams: option.baseMacros.sodiumMilligrams,
      );

  /// Which component this calibrates.
  final String componentId;

  /// Cooked mass of the standard portion, in grams.
  final double portionGrams;

  /// Grams of protein in that portion.
  final double proteinGrams;

  /// Grams of total carbohydrate, inclusive of fibre.
  final double carbohydrateGrams;

  /// Grams of fat.
  final double fatGrams;

  /// Grams of dietary fibre.
  final double dietaryFiberGrams;

  /// Milligrams of sodium.
  final double sodiumMilligrams;

  /// Why the manager is changing it.
  final String? note;

  /// Returns a copy with one field replaced.
  CalibrationDraft withField(CalibrationField field, double value) =>
      switch (field) {
        CalibrationField.portionGrams => copyWith(portionGrams: value),
        CalibrationField.protein => copyWith(proteinGrams: value),
        CalibrationField.carbohydrate => copyWith(carbohydrateGrams: value),
        CalibrationField.fat => copyWith(fatGrams: value),
        CalibrationField.fibre => copyWith(dietaryFiberGrams: value),
        CalibrationField.sodium => copyWith(sodiumMilligrams: value),
      };

  /// Reads one field.
  double valueOf(CalibrationField field) => switch (field) {
        CalibrationField.portionGrams => portionGrams,
        CalibrationField.protein => proteinGrams,
        CalibrationField.carbohydrate => carbohydrateGrams,
        CalibrationField.fat => fatGrams,
        CalibrationField.fibre => dietaryFiberGrams,
        CalibrationField.sodium => sodiumMilligrams,
      };

  /// Returns a copy with the given fields replaced.
  CalibrationDraft copyWith({
    double? portionGrams,
    double? proteinGrams,
    double? carbohydrateGrams,
    double? fatGrams,
    double? dietaryFiberGrams,
    double? sodiumMilligrams,
    String? note,
  }) =>
      CalibrationDraft(
        componentId: componentId,
        portionGrams: portionGrams ?? this.portionGrams,
        proteinGrams: proteinGrams ?? this.proteinGrams,
        carbohydrateGrams: carbohydrateGrams ?? this.carbohydrateGrams,
        fatGrams: fatGrams ?? this.fatGrams,
        dietaryFiberGrams: dietaryFiberGrams ?? this.dietaryFiberGrams,
        sodiumMilligrams: sodiumMilligrams ?? this.sodiumMilligrams,
        note: note ?? this.note,
      );

  /// The macro mass the draft accounts for, in grams.
  double get accountedGrams => proteinGrams + carbohydrateGrams + fatGrams;

  /// Whether this draft says anything different from [option].
  bool differsFrom(IngredientOption option) =>
      portionGrams != option.basePortionGrams ||
      proteinGrams != option.baseMacros.proteinGrams ||
      carbohydrateGrams != option.baseMacros.carbohydrateGrams ||
      fatGrams != option.baseMacros.fatGrams ||
      dietaryFiberGrams != option.baseMacros.dietaryFiberGrams ||
      sodiumMilligrams != option.baseMacros.sodiumMilligrams;

  /// Everything wrong or suspicious about this draft, against [published].
  ///
  /// Ordered blocking-first, so a form showing only the top finding shows the
  /// one that matters.
  List<CalibrationFinding> review(IngredientOption published) {
    final List<CalibrationFinding> blocking = <CalibrationFinding>[];
    final List<CalibrationFinding> advisory = <CalibrationFinding>[];

    void block(CalibrationField field, LocalizedText message) => blocking.add(
          CalibrationFinding(
            severity: CalibrationSeverity.blocking,
            field: field,
            message: message,
          ),
        );
    void advise(CalibrationField field, LocalizedText message) => advisory.add(
          CalibrationFinding(
            severity: CalibrationSeverity.advisory,
            field: field,
            message: message,
          ),
        );

    for (final CalibrationField field in CalibrationField.values) {
      final double value = valueOf(field);
      if (value.isNaN || value.isInfinite) {
        block(
          field,
          const LocalizedText(ar: 'أدخل رقمًا', en: 'Enter a number'),
        );
      } else if (value < 0) {
        block(
          field,
          const LocalizedText(
            ar: 'لا يمكن أن يكون بالسالب',
            en: 'Cannot be negative',
          ),
        );
      }
    }
    if (blocking.isNotEmpty) return blocking;

    if (portionGrams <= 0) {
      block(
        CalibrationField.portionGrams,
        const LocalizedText(
          ar: 'الحصة يجب أن تكون أكبر من صفر',
          en: 'A portion has to weigh something',
        ),
      );
    }

    // The constraint that would otherwise assert its way out of the app.
    if (dietaryFiberGrams > carbohydrateGrams) {
      block(
        CalibrationField.fibre,
        const LocalizedText(
          ar: 'الألياف جزء من الكربوهيدرات ولا يمكن أن تتجاوزها',
          en: 'Fibre is part of the carbohydrate and cannot exceed it',
        ),
      );
    }

    // Physics. What is not protein, carbohydrate or fat is water, ash and
    // minerals — so the macros can never outweigh the portion carrying them.
    if (portionGrams > 0 && accountedGrams > portionGrams) {
      block(
        CalibrationField.portionGrams,
        LocalizedText(
          ar: 'المغذيات ${accountedGrams.round()} جم داخل حصة '
              '${portionGrams.round()} جم',
          en: '${accountedGrams.round()}g of macros in a '
              '${portionGrams.round()}g portion',
        ),
      );
    }

    if (blocking.isNotEmpty) return blocking;

    // Advisory from here: allowed, but a manager is told.
    if (portionGrams > 0 && accountedGrams / portionGrams > 0.92) {
      advise(
        CalibrationField.portionGrams,
        const LocalizedText(
          ar: 'لا ماء تقريبًا في هذه الحصة — تحقّق من الميزان',
          en: 'Almost no water in this portion — check the scale',
        ),
      );
    }

    for (final CalibrationField field in CalibrationField.values) {
      final double was = _publishedValue(published, field);
      final double now = valueOf(field);
      if (was <= 0) continue;
      final double drift = (now - was).abs() / was;
      if (drift > 0.25) {
        advise(
          field,
          LocalizedText(
            ar: 'تغيّر ${(drift * 100).round()}٪ عن المنشور',
            en: '${(drift * 100).round()}% away from what is published',
          ),
        );
      }
    }

    return <CalibrationFinding>[...blocking, ...advisory];
  }

  /// Whether this draft can be saved.
  bool canCommit(IngredientOption published) =>
      !review(published).any((CalibrationFinding f) => f.isBlocking);

  /// Turns the draft into a calibration.
  ///
  /// Throws when a blocking finding stands. Callers gate on [canCommit]; the
  /// throw is the backstop that makes it impossible to publish a panel that
  /// describes an impossible food by skipping the check.
  RecipeCalibration commit({
    required IngredientOption published,
    required String by,
    required DateTime at,
  }) {
    final List<CalibrationFinding> findings = review(published);
    if (findings.any((CalibrationFinding f) => f.isBlocking)) {
      throw StateError(
        'cannot commit a calibration for $componentId with blocking findings: '
        '${findings.where((CalibrationFinding f) => f.isBlocking).toList()}',
      );
    }
    return RecipeCalibration._(
      componentId: componentId,
      portionGrams: portionGrams,
      macros: MacroProfile(
        proteinGrams: proteinGrams,
        carbohydrateGrams: carbohydrateGrams,
        fatGrams: fatGrams,
        dietaryFiberGrams: dietaryFiberGrams,
        sodiumMilligrams: sodiumMilligrams,
      ),
      by: by,
      at: at,
      note: note,
      advisories: findings,
    );
  }

  static double _publishedValue(
    IngredientOption option,
    CalibrationField field,
  ) =>
      switch (field) {
        CalibrationField.portionGrams => option.basePortionGrams,
        CalibrationField.protein => option.baseMacros.proteinGrams,
        CalibrationField.carbohydrate => option.baseMacros.carbohydrateGrams,
        CalibrationField.fat => option.baseMacros.fatGrams,
        CalibrationField.fibre => option.baseMacros.dietaryFiberGrams,
        CalibrationField.sodium => option.baseMacros.sodiumMilligrams,
      };
}

/// A committed measurement that supersedes what a component publishes.
///
/// Immutable and stamped. A calibration changes a figure a guest makes a
/// dietary decision on, so who changed it, when, and why are part of the
/// record rather than a log line somewhere else — a nutrition panel that
/// cannot be traced back to a person is one nobody can defend.
final class RecipeCalibration {
  const RecipeCalibration._({
    required this.componentId,
    required this.portionGrams,
    required this.macros,
    required this.by,
    required this.at,
    required this.advisories,
    this.note,
  });

  /// Which component this supersedes.
  final String componentId;

  /// Measured cooked mass of the standard portion.
  final double portionGrams;

  /// Measured macronutrients of that portion.
  final MacroProfile macros;

  /// Who measured it.
  final String by;

  /// When.
  final DateTime at;

  /// Why, if they said.
  final String? note;

  /// Findings that were outstanding, and accepted, at the time it was saved.
  final List<CalibrationFinding> advisories;

  /// How much the portion moved against [published], as a factor.
  ///
  /// This is what the store has to follow. A portion calibrated 10% heavier
  /// draws 10% more raw, and an inventory that does not move with the recipe
  /// is an inventory that is wrong from the moment the recipe changes.
  double portionFactorAgainst(IngredientOption published) =>
      published.basePortionGrams <= 0
          ? 1
          : portionGrams / published.basePortionGrams;

  @override
  String toString() =>
      'RecipeCalibration($componentId, ${portionGrams.round()}g, by $by)';
}
