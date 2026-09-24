import 'package:flutter_test/flutter_test.dart';
import 'package:mawzoon/core/localization/localized_text.dart';
import 'package:mawzoon/features/cart_checkout/domain/delivery_address.dart';
import 'package:mawzoon/features/mindful_satiety/application/reflection_controller.dart';
import 'package:mawzoon/features/mindful_satiety/data/reflection_notifier.dart';
import 'package:mawzoon/features/mindful_satiety/data/reflection_store.dart';
import 'package:mawzoon/features/mindful_satiety/domain/reflection_journal.dart';
import 'package:mawzoon/features/mindful_satiety/domain/satiety_answer.dart';

import 'reflection_fixtures.dart';

class _Harness {
  _Harness({DateTime? start, ReflectionRecord? record})
      : clock = start ?? noon,
        store = InMemoryReflectionStore(record) {
    controller = ReflectionController(
      store: store,
      notifier: notifier,
      now: () => clock,
    );
  }

  DateTime clock;
  final InMemoryReflectionStore store;
  final FakeReflectionNotifier notifier = FakeReflectionNotifier();
  late final ReflectionController controller;

  void advance(Duration d) => clock = clock.add(d);
}

void main() {
  late _Harness h;

  setUp(() async {
    h = _Harness();
    await h.controller.start();
  });

  tearDown(() => h.controller.dispose());

  test('placing an order schedules one question, saved first', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);

    final PendingReflection pending = h.controller.record.pending!;
    expect(pending.dueAt, noon.add(const Duration(minutes: 90)));
    expect(h.notifier.scheduled!.payload, pending.id);
    expect(h.notifier.scheduled!.at, pending.dueAt);
    expect(h.notifier.scheduled!.language, AppLanguage.arabic);
    expect((await h.store.load()).pending!.id, pending.id);
    // Not askable yet.
    expect(h.controller.askable, isNull);
  });

  test('permission is asked once, ever', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    expect(h.notifier.permissionRequests, 1);
  });

  test('a second order replaces the first question', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    final String first = h.controller.record.pending!.id;
    h.advance(const Duration(minutes: 5));
    await h.controller.orderPlaced(
      draft(mode: FulfilmentMode.pickup),
      language: AppLanguage.english,
    );
    expect(h.controller.record.pending!.id, isNot(first));
    expect(h.notifier.scheduled!.payload, h.controller.record.pending!.id);
    expect(h.notifier.scheduled!.language, AppLanguage.english);
  });

  test('no notification when due in quiet hours; the card still waits',
      () async {
    final _Harness late = _Harness(start: DateTime(2026, 9, 24, 21));
    await late.controller.start();
    await late.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    expect(late.notifier.scheduled, isNull);
    late.advance(const Duration(minutes: 90));
    expect(late.controller.askable, isNotNull);
    late.controller.dispose();
  });

  test('answering records both answers and clears the question', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    h.advance(const Duration(minutes: 95));
    await h.controller.answer(SatietyLevel.heavy, EnergyLevel.calm);

    final ReflectionRecord r = h.controller.record;
    expect(r.pending, isNull);
    expect(r.totalAnswered, 1);
    expect(r.journal.entries.single.satiety, SatietyLevel.heavy);
    expect(r.journal.entries.single.energy, EnergyLevel.calm);
    expect(h.notifier.scheduled, isNull);
  });

  test('answering before it is due, or after expiry, does nothing', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    await h.controller.answer(SatietyLevel.light, EnergyLevel.calm);
    expect(h.controller.record.journal.entries, isEmpty);

    h.advance(const Duration(minutes: 90) + const Duration(hours: 4));
    await h.controller.answer(SatietyLevel.light, EnergyLevel.calm);
    expect(h.controller.record.journal.entries, isEmpty);
  });

  test('skip stores nothing', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    h.advance(const Duration(minutes: 95));
    await h.controller.skip();
    expect(h.controller.record.pending, isNull);
    expect(h.controller.record.journal.entries, isEmpty);
    expect(h.controller.record.totalAnswered, 0);
  });

  test('a stale question is dropped on start', () async {
    final _Harness later = _Harness(
      start: noon.add(const Duration(hours: 9)),
      record: ReflectionRecord(
        pending: PendingReflection(id: 'old', snapshot: snapshot(), dueAt: noon),
      ),
    );
    await later.controller.start();
    expect(later.controller.record.pending, isNull);
    expect((await later.store.load()).pending, isNull);
    later.controller.dispose();
  });

  test('a notification tap asks for the sheet; an old one does not', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    h.advance(const Duration(minutes: 95));

    h.notifier.onTap!('some-replaced-order');
    expect(h.controller.sheetRequested, isFalse);

    h.notifier.onTap!(h.controller.record.pending!.id);
    expect(h.controller.sheetRequested, isTrue);
    h.controller.consumeSheetRequest();
    expect(h.controller.sheetRequested, isFalse);
  });

  test('cold start from the notification asks for the sheet', () async {
    final _Harness cold = _Harness(
      start: noon.add(const Duration(minutes: 5)),
      record: ReflectionRecord(
        pending: PendingReflection(id: 'q', snapshot: snapshot(), dueAt: noon),
      ),
    );
    cold.notifier.launchedWith = 'q';
    await cold.controller.start();
    expect(cold.controller.sheetRequested, isTrue);
    cold.controller.dispose();
  });

  test('the snapshot is the plate as ordered', () async {
    await h.controller.orderPlaced(draft(), language: AppLanguage.arabic);
    final snap = h.controller.record.pending!.snapshot;
    expect(snap.componentNames, hasLength(3));
    expect(snap.kilocalories, greaterThan(0));
    expect(snap.placedAt, noon);
  });
}
