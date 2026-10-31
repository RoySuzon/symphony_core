import '../../auth/domain/entities/auth_tokens.dart';

/// Persists the authentication session (tokens and user payload).
///
/// The default implementation (`SecureSessionStorage`) stores everything in a
/// `KeyValueStorage` backed by the platform secure storage.
abstract class SessionStorage {
  /// Allows subclasses to have const constructors.
  const SessionStorage();

  /// Returns the persisted tokens, or `null` when there is no session.
  Future<AuthTokens?> readTokens();

  /// Persists [tokens], replacing previous tokens.
  Future<void> writeTokens(AuthTokens tokens);

  /// Returns the persisted user payload, or `null`.
  Future<Map<String, Object?>?> readUser();

  /// Persists the user payload.
  Future<void> writeUser(Map<String, Object?> user);

  /// Removes tokens and user payload.
  Future<void> clear();
}
