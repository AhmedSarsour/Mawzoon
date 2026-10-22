import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/staff_auth/domain/staff_auth.dart';
import 'supabase_service.dart';

/// Staff sign-in on Supabase: email + password, then the `is_staff()` check.
final class SupabaseStaffAuth implements StaffAuth {
  /// Creates the auth. The client is resolved on each call.
  SupabaseStaffAuth({
    SupabaseClient Function()? client,
    Future<bool> Function()? isStaff,
  })  : _client = client ?? (() => SupabaseService.client),
        _isStaff = isStaff ?? SupabaseService.isStaffSession;

  final SupabaseClient Function() _client;
  final Future<bool> Function() _isStaff;

  @override
  Future<StaffAccess> current() async {
    try {
      final User? user = _client().auth.currentUser;
      if (user == null) return const StaffSignedOut();
      return await _isStaff()
          ? const StaffSignedIn()
          : StaffNotOnTeam(user.email);
    } catch (error) {
      debugPrint('staff access check failed: $error');
      return const StaffSignedOut();
    }
  }

  @override
  Future<(StaffAccess?, StaffSignInFailure?)> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client().auth.signInWithPassword(
            email: email.trim(),
            password: password,
          );
    } on AuthApiException catch (error) {
      // 400 is GoTrue's answer for a wrong email/password pair.
      if (error.statusCode == '400') {
        return (null, StaffSignInFailure.wrongCredentials);
      }
      debugPrint('staff sign-in failed: $error');
      return (null, StaffSignInFailure.unreachable);
    } catch (error) {
      debugPrint('staff sign-in failed: $error');
      return (null, StaffSignInFailure.unreachable);
    }
    final StaffAccess access = await current();
    return (access, null);
  }

  @override
  Future<void> signOut() async {
    try {
      await _client().auth.signOut();
    } catch (error) {
      debugPrint('staff sign-out failed: $error');
    }
  }
}
