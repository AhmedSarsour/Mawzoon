import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/nutrition/glycemic.dart';
import 'package:mawzoon/core/nutrition/portion_scale.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/mindful_satiety/data/reflection_codec.dart';
import 'package:mawzoon/features/mindful_satiety/data/reflection_store.dart';
import 'package:mawzoon/features/mindful_satiety/domain/reflection_journal.dart';
import 'package:mawzoon/features/mindful_satiety/domain/reflection_timing.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_answer.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_insight.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reflection_fixtures.dart';

void main() {
  group('timing', () {
    test('delivery is asked 90 minutes after ordering, pickup 60', () {
      expect(
        ReflectionTiming.dueAt(noon, FulfilmentMode.delivery),
        noon.add(const Duration(minutes: 90)),
      );
      expect(
        ReflectionTiming.dueAt(noon, FulfilmentMode.pickup),
        noon.add(const Duration(minutes: 60)),
      );
    });

    test('quiet hours run 22:00 to 07:00', () {
      bool quiet(int h, [int m = 0]) =>
          ReflectionTiming.isQuietHour(DateTime(2026, 9, 24, h, m));
      expect(quiet(21, 59), isFalse);
      expect(quiet(22), isTrue);
      expect(quiet(3), isTrue);
      expect(quiet(6, 59), isTrue);
      expect(quiet(7), isFalse);
    });

    test('askable from due until four hours later, not after', () {
      final PendingReflection p =
          PendingReflection(id: 'a', snapshot: snapshot(), dueAt: noon);
      expect(p.isAskableAt(noon.subtract(const Duration(seconds: 1))), isFalse);
      expect(p.isAskableAt(noon), isTrue);
      expect(p.isAskableAt(noon.add(const Duration(hours: 3, minutes: 59))), isTrue);
      expect(p.isAskableAt(noon.add(const Duration(hours: 4))), isFalse);
      expect(p.isExpiredAt(noon.add(const Duration(hours: 4))), isTrue);
    });
  });

  group('codec', () {
    final ReflectionRecord full = ReflectionRecord(
      pending: PendingReflection(
        id: 'p1',
        snapshot: snapshot(
          scale: PortionScale.athleticLoad,
          balance: GlycemicBalance.quick,
        ),
        dueAt: noon,
      ),
      journal: ReflectionJournal(<MealReflection>[
        reflection(id: 2, satiety: SatietyLevel.heavy),
        reflection(id: 1, energy: EnergyLevel.sluggish),
      ]),
      totalAnswered: 41,
      dismissedAt: const <InsightKind, int>{InsightKind.carbRelease: 38},
      askedPermission: true,
    );

    test('round-trips every field', () {
      final ReflectionRecord back =
          ReflectionCodec.decode(ReflectionCodec.encode(full));
      expect(back.pending!.id, 'p1');
      expect(back.pending!.dueAt, noon);
      expect(back.pending!.snapshot.scale, PortionScale.athleticLoad);
      expect(back.pending!.snapshot.glycemicBalance, GlycemicBalance.quick);
      expect(back.pending!.snapshot.componentNames.single.ar, 'دجاج');
      expect(back.pending!.snapshot.kilocalories, 550);
      expect(back.journal.entries.map((MealReflection r) => r.id), <String>[
        '2',
        '1',
      ]);
      expect(back.journal.entries.first.satiety, SatietyLevel.heavy);
      expect(back.journal.entries.last.energy, EnergyLevel.sluggish);
      expect(back.totalAnswered, 41);
      expect(back.dismissedAt, <InsightKind, int>{InsightKind.carbRelease: 38});
      expect(back.askedPermission, isTrue);
    });

    test('null, garbage, wrong shape and wrong version all give empty', () {
      for (final String? source in <String?>[
        null,
        '',
        '{not json',
        '[1,2]',
        '{"version": 99}',
      ]) {
        final ReflectionRecord r = ReflectionCodec.decode(source);
        expect(r.pending, isNull, reason: '$source');
        expect(r.journal.entries, isEmpty, reason: '$source');
      }
    });

    test('an entry this version cannot read is skipped, the rest survive', () {
      final String encoded = ReflectionCodec.encode(full)
          .replaceFirst('"satiety":"heavy"', '"satiety":"ravenous"');
      final ReflectionRecord back = ReflectionCodec.decode(encoded);
      expect(back.journal.entries.map((MealReflection r) => r.id), <String>['1']);
      expect(back.pending, isNotNull);
    });
  });

  test('shared-preferences store round-trips through the plugin', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferencesReflectionStore store =
        SharedPreferencesReflectionStore();
    expect((await store.load()).journal.entries, isEmpty);
    await store.save(recordOf(<MealReflection>[reflection(id: 7)]));
    expect(
      (await SharedPreferencesReflectionStore().load()).journal.entries.single.id,
      '7',
    );
  });
}
