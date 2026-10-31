import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'symphony_core.dart';

/// Exposes the services of a [SymphonyCore] to the widget tree.
///
/// It is an `UncontrolledProviderScope` bound to the container of [core]
/// (or of [SymphonyCore.instance] when [core] is `null`), so every widget
/// below can use the providers of this package with the regular Riverpod
/// APIs (`ConsumerWidget`, `ref.watch(...)`).
///
/// ```dart
/// await SymphonyCore.initialize(config: config);
/// runApp(const SymphonyScope(child: MyApp()));
/// ```
///
/// [SymphonyCore.wrap] is a shortcut for `SymphonyScope(core: core, ...)`.
/// The scope does not own the instance: dispose it with
/// [SymphonyCore.dispose].
class SymphonyScope extends StatelessWidget {
  /// Creates a scope for [core], or for the global [SymphonyCore.instance]
  /// when [core] is `null` (which must then be initialized before this
  /// widget builds).
  const SymphonyScope({super.key, this.core, required this.child});

  /// The instance whose services are exposed. Defaults to
  /// [SymphonyCore.instance].
  final SymphonyCore? core;

  /// The widget below this scope, usually the application widget.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: (core ?? SymphonyCore.instance).container,
      child: child,
    );
  }
}
