import 'dart:convert';

import '../../../core/localization/localized_text.dart';
import '../../../core/nutrition/glycemic.dart';
import '../../../core/nutrition/portion_scale.dart';
import '../domain/meal_snapshot.dart';
import '../domain/reflection_journal.dart';
import '../domain/satiety_answer.dart';
import '../domain/satiety_insight.dart';

/// JSON for [ReflectionRecord]. Decoding never throws: corrupt data becomes an
/// empty record, and an entry this version can't read (say, an enum a future
/// version added) is skipped while the rest survive.
abstract final class ReflectionCodec {
  /// Bumped when the shape changes incompatibly.
  static const int version = 1;

  /// Encodes [record].
  static String encode(ReflectionRecord record) => jsonEncode(<String, Object?>{
        'version': version,
        'pending': record.pending == null ? null : _pending(record.pending!),
        'journal': <Object>[
          for (final MealReflection r in record.journal.entries) _reflection(r),
        ],
        'totalAnswered': record.totalAnswered,
        'dismissedAt': <String, int>{
          for (final MapEntry<InsightKind, int> e in record.dismissedAt.entries)
            e.key.name: e.value,
        },
        'askedPermission': record.askedPermission,
      });

  /// Decodes [source]; `null`, corrupt or foreign data yields an empty record.
  static ReflectionRecord decode(String? source) {
    if (source == null) return ReflectionRecord.empty;
    try {
      final Object? raw = jsonDecode(source);
      if (raw is! Map<String, Object?> || raw['version'] != version) {
        return ReflectionRecord.empty;
      }
      final Object? pending = raw['pending'];
      final Object? journal = raw['journal'];
      final Object? dismissed = raw['dismissedAt'];
      return ReflectionRecord(
        pending: pending is Map<String, Object?> ? _tryPending(pending) : null,
        journal: ReflectionJournal(<MealReflection>[
          if (journal is List<Object?>)
            for (final Object? entry in journal)
              if (entry is Map<String, Object?>)
                ...<MealReflection?>[_tryReflection(entry)]
                    .whereType<MealReflection>(),
        ]),
        totalAnswered: _int(raw['totalAnswered']) ?? 0,
        dismissedAt: <InsightKind, int>{
          if (dismissed is Map<String, Object?>)
            for (final MapEntry<String, Object?> e in dismissed.entries)
              if (_byName(InsightKind.values, e.key) != null &&
                  _int(e.value) != null)
                _byName(InsightKind.values, e.key)!: _int(e.value)!,
        },
        askedPermission: raw['askedPermission'] == true,
      );
    } on FormatException {
      return ReflectionRecord.empty;
    }
  }

  // ---- encoding ----

  static Map<String, Object?> _pending(PendingReflection p) => <String, Object?>{
        'id': p.id,
        'dueAt': p.dueAt.toUtc().toIso8601String(),
        'snapshot': _snapshot(p.snapshot),
      };

  static Map<String, Object?> _reflection(MealReflection r) =>
      <String, Object?>{
        'id': r.id,
        'satiety': r.satiety.name,
        'energy': r.energy.name,
        'answeredAt': r.answeredAt.toUtc().toIso8601String(),
        'snapshot': _snapshot(r.snapshot),
      };

  static Map<String, Object?> _snapshot(MealSnapshot s) => <String, Object?>{
        'placedAt': s.placedAt.toUtc().toIso8601String(),
        'scale': s.scale.name,
        'glycemicBalance': s.glycemicBalance.name,
        'components': <Object>[
          for (final LocalizedText n in s.componentNames)
            <String, String>{'ar': n.ar, 'en': n.en},
        ],
        'kcal': s.kilocalories,
        'protein': s.proteinEnergyShare,
        'carb': s.carbohydrateEnergyShare,
        'fat': s.fatEnergyShare,
        'fiber': s.fiberGrams,
      };

  // ---- decoding: each returns null on anything it can't read ----

  static PendingReflection? _tryPending(Map<String, Object?> m) {
    final String? id = _string(m['id']);
    final DateTime? dueAt = _date(m['dueAt']);
    final MealSnapshot? snapshot = _trySnapshot(m['snapshot']);
    if (id == null || dueAt == null || snapshot == null) return null;
    return PendingReflection(id: id, snapshot: snapshot, dueAt: dueAt);
  }

  static MealReflection? _tryReflection(Map<String, Object?> m) {
    final String? id = _string(m['id']);
    final SatietyLevel? satiety = _byName(SatietyLevel.values, m['satiety']);
    final EnergyLevel? energy = _byName(EnergyLevel.values, m['energy']);
    final DateTime? answeredAt = _date(m['answeredAt']);
    final MealSnapshot? snapshot = _trySnapshot(m['snapshot']);
    if (id == null ||
        satiety == null ||
        energy == null ||
        answeredAt == null ||
        snapshot == null) {
      return null;
    }
    return MealReflection(
      id: id,
      snapshot: snapshot,
      satiety: satiety,
      energy: energy,
      answeredAt: answeredAt,
    );
  }

  static MealSnapshot? _trySnapshot(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final DateTime? placedAt = _date(raw['placedAt']);
    final PortionScale? scale = _byName(PortionScale.values, raw['scale']);
    final GlycemicBalance? balance =
        _byName(GlycemicBalance.values, raw['glycemicBalance']);
    final Object? components = raw['components'];
    final double? kcal = _double(raw['kcal']);
    final double? protein = _double(raw['protein']);
    final double? carb = _double(raw['carb']);
    final double? fat = _double(raw['fat']);
    final double? fiber = _double(raw['fiber']);
    if (placedAt == null ||
        scale == null ||
        balance == null ||
        components is! List<Object?> ||
        kcal == null ||
        protein == null ||
        carb == null ||
        fat == null ||
        fiber == null) {
      return null;
    }
    return MealSnapshot(
      placedAt: placedAt,
      scale: scale,
      glycemicBalance: balance,
      componentNames: <LocalizedText>[
        for (final Object? c in components)
          if (c is Map<String, Object?> &&
              _string(c['ar']) != null &&
              _string(c['en']) != null)
            LocalizedText(ar: _string(c['ar'])!, en: _string(c['en'])!),
      ],
      kilocalories: kcal,
      proteinEnergyShare: protein,
      carbohydrateEnergyShare: carb,
      fatEnergyShare: fat,
      fiberGrams: fiber,
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final T v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static String? _string(Object? v) => v is String ? v : null;

  static int? _int(Object? v) => v is int ? v : null;

  static double? _double(Object? v) => v is num ? v.toDouble() : null;

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}
