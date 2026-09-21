import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/core/nutrition/macro_targets.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';

void main() {
  group('targets per portion', () {
    test('the athletic load aims higher than the house portion', () {
      expect(
        MacroTargets.athletic.proteinGrams,
        greaterThan(MacroTargets.standard.proteinGrams),
      );
      expect(
        MacroTargets.athletic.fiberGrams,
        greaterThan(MacroTargets.standard.fiberGrams),
      );
    });

    test('resolve by scale', () {
      expect(MacroTargets.forScale(PortionScale.standardBalance),
          MacroTargets.standard,);
      expect(MacroTargets.forScale(PortionScale.athleticLoad),
          MacroTargets.athletic,);
    });
  });

  group('progress', () {
    const MacroTargets targets = MacroTargets.standard; // 40 g protein

    test('reports the fraction reached', () {
      expect(targets.proteinProgress(0), 0);
      expect(targets.proteinProgress(20), closeTo(0.5, 1e-9));
      expect(targets.proteinProgress(40), 1);
    });

    // A target, not a cap. The distinction is the whole reason this type is
    // separate from the energy band.
    test('clamps above the target rather than overshooting', () {
      expect(targets.proteinProgress(80), 1);
      expect(targets.rawProteinProgress(80), closeTo(2, 1e-9));
    });

    test('meeting the target is a threshold, not a range', () {
      expect(targets.meetsProtein(39.9), isFalse);
      expect(targets.meetsProtein(40), isTrue);
      expect(targets.meetsProtein(120), isTrue);
    });

    test('fibre works the same way', () {
      expect(targets.fiberProgress(4), closeTo(0.5, 1e-9));
      expect(targets.fiberProgress(99), 1);
      expect(targets.meetsFiber(8), isTrue);
    });
  });

  group('captions', () {
    const MacroTargets targets = MacroTargets.standard;

    test('read the same way whether the target is met or not', () {
      final LocalizedText below = targets.proteinCaption(20);
      final LocalizedText met = targets.proteinCaption(50);

      expect(below.ar.trim(), isNotEmpty);
      expect(below.en.trim(), isNotEmpty);
      expect(met.ar.trim(), isNotEmpty);
      expect(met.en.trim(), isNotEmpty);
      expect(below, isNot(met));

      // Neither caption scolds: no "too", no "over", no exclamation.
      for (final LocalizedText caption in <LocalizedText>[below, met]) {
        expect(caption.en.toLowerCase(), isNot(contains('too')));
        expect(caption.en, isNot(contains('!')));
      }
    });
  });

  group('value semantics', () {
    test('compares by field', () {
      expect(
        const MacroTargets(proteinGrams: 40, fiberGrams: 8),
        MacroTargets.standard,
      );
      expect(MacroTargets.standard, isNot(MacroTargets.athletic));
    });

    test('rejects a non-positive target', () {
      expect(
        () => MacroTargets(proteinGrams: 0, fiberGrams: 8),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
