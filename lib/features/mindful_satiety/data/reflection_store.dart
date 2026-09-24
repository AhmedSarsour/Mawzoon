import 'package:shared_preferences/shared_preferences.dart';

import '../domain/reflection_journal.dart';
import 'reflection_codec.dart';

/// Where the loop keeps its [ReflectionRecord]. On the device only.
abstract interface class ReflectionStore {
  /// The saved record, or an empty one.
  Future<ReflectionRecord> load();

  /// Replaces the saved record.
  Future<void> save(ReflectionRecord record);
}

/// Keeps the record in memory. For tests and previews.
final class InMemoryReflectionStore implements ReflectionStore {
  /// Creates a store, optionally already holding [record].
  InMemoryReflectionStore([ReflectionRecord? record])
      : _record = record ?? ReflectionRecord.empty;

  ReflectionRecord _record;

  /// How many times [save] ran.
  int saves = 0;

  @override
  Future<ReflectionRecord> load() async => _record;

  @override
  Future<void> save(ReflectionRecord record) async {
    saves++;
    _record = record;
  }
}

/// One JSON string under one key in [SharedPreferences].
final class SharedPreferencesReflectionStore implements ReflectionStore {
  /// Creates the store. The plugin is resolved on first use, not here.
  SharedPreferencesReflectionStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  /// The key. The suffix is the codec version.
  static const String key = 'mawzoon.reflection.v1';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<ReflectionRecord> load() async =>
      ReflectionCodec.decode((await _preferences()).getString(key));

  @override
  Future<void> save(ReflectionRecord record) async {
    await (await _preferences()).setString(key, ReflectionCodec.encode(record));
  }
}
