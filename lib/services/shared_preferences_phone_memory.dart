import 'package:shared_preferences/shared_preferences.dart';

import '../features/cart_checkout/domain/guest_phone.dart';

/// The guest's delivery phone, kept on this device under one key.
final class SharedPreferencesPhoneMemory implements PhoneMemory {
  /// Creates the memory.
  SharedPreferencesPhoneMemory({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  /// The storage key.
  static const String key = 'mawzoon.guest_phone.v1';

  @override
  Future<String?> read() async {
    final String? stored = (await _preferences()).getString(key);
    // Re-validated on the way out: a value from an older build that no longer
    // passes is treated as never given, not sent to the kitchen.
    return stored == null ? null : saudiMobile(stored);
  }

  @override
  Future<void> write(String e164) async =>
      (await _preferences()).setString(key, e164);
}
