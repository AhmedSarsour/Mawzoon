import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/glycemic.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../../cart_checkout/domain/order_draft.dart';
import '../data/reflection_notifier.dart';
import '../data/reflection_store.dart';
import '../domain/meal_snapshot.dart';
import '../domain/reflection_journal.dart';
import '../domain/reflection_timing.dart';
import '../domain/satiety_answer.dart';
import '../domain/satiety_correlation.dart';
import '../domain/satiety_insight.dart';

/// The post-meal loop, as one object: one open question, the answers, and
/// what they suggest. Every change is saved before listeners hear about it.
final class ReflectionController extends ChangeNotifier {
  /// Creates the controller. Call [start] once.
  ReflectionController({
    required ReflectionStore store,
    required ReflectionNotifier notifier,
    DateTime Function()? now,
  })  : _store = store,
        _notifier = notifier,
        _now = now ?? DateTime.now;

  final ReflectionStore _store;
  final ReflectionNotifier _notifier;
  final DateTime Function() _now;

  ReflectionRecord _record = ReflectionRecord.empty;
  bool _sheetRequested = false;
  bool _disposed = false;
  Timer? _boundary;

  /// Everything kept on the device.
  ReflectionRecord get record => _record;

  /// The question, if it should be asked right now.
  PendingReflection? get askable {
    final PendingReflection? pending = _record.pending;
    return pending != null && pending.isAskableAt(_now()) ? pending : null;
  }

  /// Set when the guest tapped the notification; the home screen opens the
  /// sheet and calls [consumeSheetRequest].
  bool get sheetRequested => _sheetRequested && askable != null;

  /// Loads the record, drops a stale question, and wires notification taps.
  Future<void> start() async {
    _record = await _store.load();
    if (_record.pending?.isExpiredAt(_now()) ?? false) {
      await _commit(_record.copyWith(clearPending: true));
    }
    await _notifier.initialize(onTap: _onNotificationTap);
    _onNotificationTap(await _notifier.launchPayload());
    _armBoundary();
    _notify();
  }

  /// A guest placed [draft]. Replaces any open question with one about this
  /// meal, and schedules the notification unless it would land in quiet
  /// hours or is already in the past.
  Future<void> orderPlaced(
    OrderDraft draft, {
    required AppLanguage language,
  }) async {
    final DateTime placedAt = _now();
    final DateTime dueAt = ReflectionTiming.dueAt(placedAt, draft.mode);
    final PendingReflection pending = PendingReflection(
      id: placedAt.microsecondsSinceEpoch.toString(),
      snapshot: MealSnapshot.ofOrder(draft, placedAt: placedAt),
      dueAt: dueAt,
    );
    final bool askPermission = !_record.askedPermission;
    await _commit(_record.copyWith(pending: pending, askedPermission: true));

    await _notifier.cancel();
    if (askPermission) await _notifier.requestPermission();
    if (!ReflectionTiming.isQuietHour(dueAt) && dueAt.isAfter(_now())) {
      await _notifier.schedule(payload: pending.id, at: dueAt, language: language);
    }
  }

  /// The guest answered. Half an answer is never saved: this takes both.
  Future<void> answer(SatietyLevel satiety, EnergyLevel energy) async {
    final PendingReflection? pending = askable;
    if (pending == null) return;
    await _commit(
      _record.copyWith(
        clearPending: true,
        journal: _record.journal.add(
          MealReflection(
            id: pending.id,
            snapshot: pending.snapshot,
            satiety: satiety,
            energy: energy,
            answeredAt: _now(),
          ),
        ),
        totalAnswered: _record.totalAnswered + 1,
      ),
    );
    _sheetRequested = false;
    await _notifier.cancel();
  }

  /// "Not now". The question is dropped, nothing is recorded, nobody is
  /// asked again about this meal.
  Future<void> skip() async {
    if (_record.pending == null) return;
    await _commit(_record.copyWith(clearPending: true));
    _sheetRequested = false;
    await _notifier.cancel();
  }

  /// Hides [kind] until enough new answers arrive.
  Future<void> dismiss(InsightKind kind) => _commit(
        _record.copyWith(
          dismissedAt: <InsightKind, int>{
            ..._record.dismissedAt,
            kind: _record.totalAnswered,
          },
        ),
      );

  /// What the answers suggest for the plate on screen.
  List<SatietyInsight> insightsFor({
    required PortionScale scale,
    GlycemicBalance? balance,
  }) =>
      SatietyCorrelation.insightsFor(
        _record,
        currentScale: scale,
        currentBalance: balance,
      );

  /// The home screen has opened the sheet.
  void consumeSheetRequest() => _sheetRequested = false;

  void _onNotificationTap(String? payload) {
    // A tap on an old notification (a replaced order) opens the app and
    // nothing else.
    if (payload == null || payload != _record.pending?.id) return;
    _sheetRequested = true;
    _notify();
  }

  Future<void> _commit(ReflectionRecord next) async {
    _record = next;
    await _store.save(next);
    _armBoundary();
    _notify();
  }

  /// Wakes once when the open question becomes due, and once when it goes
  /// stale, so the home card appears and disappears without polling.
  void _armBoundary() {
    _boundary?.cancel();
    final PendingReflection? pending = _record.pending;
    if (pending == null || _disposed) return;
    final DateTime now = _now();
    final DateTime next =
        now.isBefore(pending.dueAt) ? pending.dueAt : pending.expiresAt;
    _boundary = Timer(next.difference(now), () {
      if (_record.pending?.isExpiredAt(_now()) ?? false) {
        unawaited(_commit(_record.copyWith(clearPending: true)));
      } else {
        _armBoundary();
        _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _boundary?.cancel();
    super.dispose();
  }
}
