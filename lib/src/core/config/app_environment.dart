import 'package:flutter/foundation.dart';

/// The deployment environment an application runs in.
///
/// Three common environments are predefined. Applications can declare their
/// own (for example `AppEnvironment('qa')`) without modifying this package.
@immutable
class AppEnvironment {
  /// Creates an environment identified by [name].
  const AppEnvironment(this.name, {this.isProduction = false});

  /// Local development environment.
  static const AppEnvironment development = AppEnvironment('development');

  /// Pre-production / staging environment.
  static const AppEnvironment staging = AppEnvironment('staging');

  /// Production environment.
  static const AppEnvironment production = AppEnvironment(
    'production',
    isProduction: true,
  );

  /// Unique, human readable identifier of the environment.
  final String name;

  /// Whether this environment serves real end users.
  ///
  /// Debug-only tooling (such as the API inspector) should normally be
  /// disabled when this is `true`.
  final bool isProduction;

  @override
  bool operator ==(Object other) =>
      other is AppEnvironment &&
      other.name == name &&
      other.isProduction == isProduction;

  @override
  int get hashCode => Object.hash(name, isProduction);

  @override
  String toString() => 'AppEnvironment($name)';
}
