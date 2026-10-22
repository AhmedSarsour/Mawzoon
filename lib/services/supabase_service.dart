import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where Mawzoon's backend lives.
///
/// The anon key is public by design: it ships inside every app binary, and
/// row-level security is what guards the data. A test asserts it is the anon
/// role for this project, so a service-role key can never be pasted here.
abstract final class SupabaseConfig {
  /// The project's API URL.
  static const String url = 'https://esuifisyffmbopeorupp.supabase.co';

  /// The project's anon (public) key.
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVzdWlmaXN5ZmZtYm9wZW9ydXBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0MjQxOTYsImV4cCI6MjEwODAwMDE5Nn0.IfrWu0_fif1sA0ImvUfNQH3HwlqREdDrcLwGv-xgqJY';
}

/// Starts the Supabase client once, at app launch.
abstract final class SupabaseService {
  /// Initialises the client. Returns whether it came up.
  ///
  /// Never throws: the ordering screen runs on local data today, so a backend
  /// that fails to start must not stop the app from opening.
  static Future<bool> initialize() async {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // The legacy anon JWT; the SDK treats both key formats the same way.
        publishableKey: SupabaseConfig.anonKey,
      );
      return true;
    } catch (error, stack) {
      debugPrint('Supabase failed to start: $error\n$stack');
      return false;
    }
  }

  /// The live client. Only valid after [initialize] returned true.
  static SupabaseClient get client => Supabase.instance.client;

  /// Makes sure this install has a server identity, signing in anonymously if
  /// it has none. Returns false (never throws) when that isn't possible yet —
  /// offline, or Supabase never started — so callers can try again later.
  ///
  /// The SDK keeps the session on the device, so a guest stays the same guest
  /// (and keeps seeing their orders) across launches until they reinstall.
  static Future<bool> ensureSession() async {
    try {
      if (client.auth.currentSession != null) return true;
      await client.auth.signInAnonymously();
      return true;
    } catch (error) {
      debugPrint('Anonymous sign-in failed: $error');
      return false;
    }
  }

  /// Whether this device is signed in as staff (kitchen or back office).
  /// False — never a throw — when signed out, a guest, or offline.
  static Future<bool> isStaffSession() async {
    try {
      if (client.auth.currentSession == null) return false;
      return await client.rpc<bool>('is_staff');
    } catch (error) {
      debugPrint('Staff check failed: $error');
      return false;
    }
  }
}
