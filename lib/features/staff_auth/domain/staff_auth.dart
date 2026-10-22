/// Who is at the kitchen tablet or the back office, as far as the server knows.
sealed class StaffAccess {
  const StaffAccess();
}

/// Signed in, and on the team.
final class StaffSignedIn extends StaffAccess {
  /// Creates the state.
  const StaffSignedIn();
}

/// Nobody signed in.
final class StaffSignedOut extends StaffAccess {
  /// Creates the state.
  const StaffSignedOut();
}

/// Signed in with an account that isn't on the team. The session is kept so
/// the screen can say which account it was.
final class StaffNotOnTeam extends StaffAccess {
  /// Creates the state.
  const StaffNotOnTeam(this.email);

  /// The account that tried, or null for an anonymous guest session.
  final String? email;
}

/// Why a sign-in didn't go through.
enum StaffSignInFailure {
  /// Wrong email or password. Deliberately one message for both: saying which
  /// one was wrong tells a stranger which emails have accounts.
  wrongCredentials,

  /// The server couldn't be reached.
  unreachable,
}

/// Signs staff in and out.
abstract interface class StaffAuth {
  /// Where this device stands now. Never throws: offline reads as signed out.
  Future<StaffAccess> current();

  /// Signs in. Returns the new access, or a [StaffSignInFailure].
  Future<(StaffAccess?, StaffSignInFailure?)> signIn({
    required String email,
    required String password,
  });

  /// Signs out of this device.
  Future<void> signOut();
}
