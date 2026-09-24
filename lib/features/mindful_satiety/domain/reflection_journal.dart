import 'meal_snapshot.dart';
import 'reflection_timing.dart';
import 'satiety_answer.dart';
import 'satiety_insight.dart';

/// A question waiting to be asked about one meal.
final class PendingReflection {
  /// Creates a pending reflection.
  const PendingReflection({
    required this.id,
    required this.snapshot,
    required this.dueAt,
  });

  /// Carried as the notification payload, so a tap on a stale notification
  /// can be told apart from the current question.
  final String id;

  /// The meal being asked about.
  final MealSnapshot snapshot;

  /// When the question is due.
  final DateTime dueAt;

  /// When it stops being worth asking.
  DateTime get expiresAt => ReflectionTiming.expiresAt(dueAt);

  /// Due and not yet stale.
  bool isAskableAt(DateTime now) =>
      !now.isBefore(dueAt) && now.isBefore(expiresAt);

  /// Too late to ask.
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

/// One answered question.
final class MealReflection {
  /// Creates a reflection.
  const MealReflection({
    required this.id,
    required this.snapshot,
    required this.satiety,
    required this.energy,
    required this.answeredAt,
  });

  /// Same id as the [PendingReflection] it answered.
  final String id;

  /// The meal.
  final MealSnapshot snapshot;

  /// How full.
  final SatietyLevel satiety;

  /// How energetic.
  final EnergyLevel energy;

  /// When the guest answered.
  final DateTime answeredAt;
}

/// The recent answers, newest first, capped at [capacity].
///
/// Oldest drop off first (FIFO): appetite shifts over months, and a bounded
/// list keeps every engine pass O(capacity).
final class ReflectionJournal {
  /// Creates a journal. [entries] must be newest first.
  ReflectionJournal([List<MealReflection> entries = const <MealReflection>[]])
      : entries = List<MealReflection>.unmodifiable(
          entries.take(capacity),
        );

  /// How many answers are kept.
  static const int capacity = 30;

  /// Newest first.
  final List<MealReflection> entries;

  /// A new journal with [reflection] at the front.
  ReflectionJournal add(MealReflection reflection) =>
      ReflectionJournal(<MealReflection>[reflection, ...entries]);
}

/// Everything the loop keeps on the device, as one value.
final class ReflectionRecord {
  /// Creates a record.
  ReflectionRecord({
    this.pending,
    ReflectionJournal? journal,
    this.totalAnswered = 0,
    this.dismissedAt = const <InsightKind, int>{},
    this.askedPermission = false,
  }) : journal = journal ?? ReflectionJournal();

  /// Nothing yet.
  static final ReflectionRecord empty = ReflectionRecord();

  /// The one open question, if any.
  final PendingReflection? pending;

  /// Recent answers.
  final ReflectionJournal journal;

  /// Every answer ever given here. Unlike the journal it never shrinks, so it
  /// can measure "five answers since you dismissed this". Never displayed.
  final int totalAnswered;

  /// For each dismissed insight, [totalAnswered] at the moment of dismissal.
  final Map<InsightKind, int> dismissedAt;

  /// Whether the OS permission has been asked for. Asked once, ever.
  final bool askedPermission;

  /// A copy with the given fields replaced. [clearPending] drops the question.
  ReflectionRecord copyWith({
    PendingReflection? pending,
    bool clearPending = false,
    ReflectionJournal? journal,
    int? totalAnswered,
    Map<InsightKind, int>? dismissedAt,
    bool? askedPermission,
  }) =>
      ReflectionRecord(
        pending: clearPending ? null : (pending ?? this.pending),
        journal: journal ?? this.journal,
        totalAnswered: totalAnswered ?? this.totalAnswered,
        dismissedAt: dismissedAt ?? this.dismissedAt,
        askedPermission: askedPermission ?? this.askedPermission,
      );
}
