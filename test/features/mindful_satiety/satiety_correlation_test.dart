import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/nutrition/glycemic.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/mindful_satiety/domain/reflection_journal.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_answer.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_correlation.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_insight.dart';

import 'reflection_fixtures.dart';

const PortionScale _std = PortionScale.standardBalance;
const PortionScale _ath = PortionScale.athleticLoad;

List<SatietyInsight> _insights(
  ReflectionRecord record, {
  PortionScale scale = _std,
  GlycemicBalance? balance,
}) =>
    SatietyCorrelation.insightsFor(
      record,
      currentScale: scale,
      currentBalance: balance,
    );

List<MealReflection> _answers(
  PortionScale scale,
  List<SatietyLevel> satiety,
) =>
    <MealReflection>[
      for (final SatietyLevel s in satiety) reflection(satiety: s, scale: scale),
    ];

MealReflection _energy(EnergyLevel e, GlycemicBalance b) =>
    reflection(energy: e, balance: b);

void main() {
  group('portion rule', () {
    test('silent with no answers', () {
      expect(_insights(ReflectionRecord.empty), isEmpty);
    });

    test('two heavy answers are not enough; the third speaks', () {
      const List<SatietyLevel> two = <SatietyLevel>[
        SatietyLevel.heavy,
        SatietyLevel.heavy,
      ];
      expect(_insights(recordOf(_answers(_ath, two)), scale: _ath), isEmpty);

      final List<SatietyInsight> three = _insights(
        recordOf(_answers(_ath, <SatietyLevel>[...two, SatietyLevel.heavy])),
        scale: _ath,
      );
      expect(three, hasLength(1));
      final PortionInsight insight = three.single as PortionInsight;
      expect(insight.from, _ath);
      expect(insight.suggested, _std);
      expect(insight.wasTooMuch, isTrue);
    });

    test('exactly two thirds is enough; just under is not', () {
      // 2 of 3.
      expect(
        _insights(
          recordOf(_answers(_ath, <SatietyLevel>[
            SatietyLevel.heavy,
            SatietyLevel.balanced,
            SatietyLevel.heavy,
          ]),),
          scale: _ath,
        ),
        hasLength(1),
      );
      // 3 of 5 (0.6).
      expect(
        _insights(
          recordOf(_answers(_ath, <SatietyLevel>[
            SatietyLevel.heavy,
            SatietyLevel.balanced,
            SatietyLevel.heavy,
            SatietyLevel.balanced,
            SatietyLevel.heavy,
          ]),),
          scale: _ath,
        ),
        isEmpty,
      );
      // 4 of 6.
      expect(
        _insights(
          recordOf(_answers(_ath, <SatietyLevel>[
            SatietyLevel.heavy,
            SatietyLevel.balanced,
            SatietyLevel.heavy,
            SatietyLevel.balanced,
            SatietyLevel.heavy,
            SatietyLevel.heavy,
          ]),),
          scale: _ath,
        ),
        hasLength(1),
      );
    });

    test('reads only the six most recent answers on that portion', () {
      // Six recent balanced, then many old heavy: the old ones are out of the
      // window.
      final List<MealReflection> entries = <MealReflection>[
        ..._answers(_ath, List<SatietyLevel>.filled(6, SatietyLevel.balanced)),
        ..._answers(_ath, List<SatietyLevel>.filled(10, SatietyLevel.heavy)),
      ];
      expect(_insights(recordOf(entries), scale: _ath), isEmpty);
    });

    test('answers about the other portion are ignored', () {
      final List<MealReflection> entries = <MealReflection>[
        ..._answers(_std, List<SatietyLevel>.filled(5, SatietyLevel.heavy)),
        ..._answers(_ath, <SatietyLevel>[SatietyLevel.heavy]),
      ];
      // Only one athletic answer: silent, despite five heavy standard ones.
      expect(_insights(recordOf(entries), scale: _ath), isEmpty);
    });

    test('light on standard suggests athletic', () {
      final PortionInsight insight = _insights(
        recordOf(_answers(_std, List<SatietyLevel>.filled(3, SatietyLevel.light))),
      ).single as PortionInsight;
      expect(insight.suggested, _ath);
      expect(insight.wasTooMuch, isFalse);
    });

    test('never suggests a portion that does not exist', () {
      expect(
        _insights(recordOf(
          _answers(_std, List<SatietyLevel>.filled(6, SatietyLevel.heavy)),
        ),),
        isEmpty,
      );
      expect(
        _insights(
          recordOf(
            _answers(_ath, List<SatietyLevel>.filled(6, SatietyLevel.light)),
          ),
          scale: _ath,
        ),
        isEmpty,
      );
    });

    test('dismissed: hidden for four more answers, back on the fifth', () {
      final List<MealReflection> heavy =
          _answers(_ath, List<SatietyLevel>.filled(3, SatietyLevel.heavy));
      ReflectionRecord at(int total) => ReflectionRecord(
            journal: ReflectionJournal(heavy),
            totalAnswered: total,
            dismissedAt: const <InsightKind, int>{InsightKind.portion: 10},
          );
      expect(_insights(at(10), scale: _ath), isEmpty);
      expect(_insights(at(14), scale: _ath), isEmpty);
      expect(_insights(at(15), scale: _ath), hasLength(1));
    });
  });

  group('carb release rule', () {
    const GlycemicBalance quick = GlycemicBalance.quick;
    const GlycemicBalance steady = GlycemicBalance.steady;

    List<MealReflection> contrast({
      int quickSluggish = 3,
      int quickOther = 0,
      int steadyCalm = 2,
      int steadySluggish = 0,
    }) =>
        <MealReflection>[
          for (int i = 0; i < quickSluggish; i++)
            _energy(EnergyLevel.sluggish, quick),
          for (int i = 0; i < quickOther; i++) _energy(EnergyLevel.calm, quick),
          for (int i = 0; i < steadyCalm; i++) _energy(EnergyLevel.calm, steady),
          for (int i = 0; i < steadySluggish; i++)
            _energy(EnergyLevel.sluggish, steady),
        ];

    test('speaks with the contrast, on a quick plate', () {
      expect(
        _insights(recordOf(contrast()), balance: quick).single,
        isA<CarbReleaseInsight>(),
      );
    });

    test('silent when the plate on screen is not quick-release', () {
      expect(_insights(recordOf(contrast()), balance: steady), isEmpty);
      expect(_insights(recordOf(contrast())), isEmpty);
    });

    test('needs three quick answers', () {
      expect(
        _insights(recordOf(contrast(quickSluggish: 2)), balance: quick),
        isEmpty,
      );
    });

    test('needs two non-quick answers to compare against', () {
      expect(
        _insights(recordOf(contrast(steadyCalm: 1)), balance: quick),
        isEmpty,
      );
    });

    test('sluggish everywhere is a hard week, not a carb', () {
      expect(
        _insights(
          recordOf(contrast(steadyCalm: 1, steadySluggish: 1)),
          balance: quick,
        ),
        isEmpty,
      );
      // 1 of 3 sluggish on steady is still a contrast.
      expect(
        _insights(
          recordOf(contrast(steadyCalm: 2, steadySluggish: 1)),
          balance: quick,
        ),
        hasLength(1),
      );
    });

    test('two of three sluggish on quick is enough; one of two is not', () {
      expect(
        _insights(
          recordOf(contrast(quickSluggish: 2, quickOther: 1)),
          balance: quick,
        ),
        hasLength(1),
      );
      expect(
        _insights(
          recordOf(contrast(quickSluggish: 2, quickOther: 2)),
          balance: quick,
        ),
        isEmpty,
      );
    });
  });

  test('portion comes before carb when both hold', () {
    final List<MealReflection> entries = <MealReflection>[
      // 4 of 6 light on standard; 4 of 4 quick sluggish against 2 calm.
      for (int i = 0; i < 4; i++)
        reflection(
          satiety: SatietyLevel.light,
          energy: EnergyLevel.sluggish,
          balance: GlycemicBalance.quick,
        ),
      for (int i = 0; i < 2; i++) reflection(),
    ];
    final List<SatietyInsight> insights =
        _insights(recordOf(entries), balance: GlycemicBalance.quick);
    expect(insights.map((SatietyInsight i) => i.kind), <InsightKind>[
      InsightKind.portion,
      InsightKind.carbRelease,
    ]);
  });

  test('journal keeps the newest thirty', () {
    ReflectionJournal journal = ReflectionJournal();
    for (int i = 0; i < 35; i++) {
      journal = journal.add(reflection(id: i));
    }
    expect(journal.entries, hasLength(ReflectionJournal.capacity));
    expect(journal.entries.first.id, '34');
    expect(journal.entries.last.id, '5');
  });
}
