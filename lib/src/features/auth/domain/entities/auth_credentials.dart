import 'package:flutter/foundation.dart';

/// Free-form sign-in (or registration / recovery) payload.
///
/// Projects decide which fields exist (`email`, `username`, `phone`, `otp`,
/// `tenant`...). The configured `AuthAdapter` turns them into the request body
/// expected by the backend.
@immutable
class AuthCredentials {
  /// Creates credentials from arbitrary [fields].
  const AuthCredentials(this.fields);

  /// E-mail + password credentials (`{'email': ..., 'password': ...}`).
  factory AuthCredentials.emailPassword({
    required String email,
    required String password,
  }) =>
      AuthCredentials(<String, Object?>{'email': email, 'password': password});

  /// Username + password credentials
  /// (`{'username': ..., 'password': ...}`).
  factory AuthCredentials.usernamePassword({
    required String username,
    required String password,
  }) =>
      AuthCredentials(
        <String, Object?>{'username': username, 'password': password},
      );

  /// The raw fields.
  final Map<String, Object?> fields;

  /// Returns the field [key] as a string, or `null`.
  String? operator [](String key) {
    final value = fields[key];
    return value?.toString();
  }

  /// Returns a copy with [other] merged into the fields.
  AuthCredentials merge(Map<String, Object?> other) =>
      AuthCredentials(<String, Object?>{...fields, ...other});

  @override
  bool operator ==(Object other) =>
      other is AuthCredentials && mapEquals(other.fields, fields);

  @override
  int get hashCode => Object.hashAllUnordered(fields.keys);

  /// Never prints the values (they usually contain secrets).
  @override
  String toString() => 'AuthCredentials(fields: ${fields.keys.toList()})';
}
