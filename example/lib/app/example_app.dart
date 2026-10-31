import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../features/settings/presentation/settings_providers.dart';
import 'app_router.dart';
import 'app_theme.dart';

/// The example application.
///
/// It must be placed below a `SymphonyScope` (see `main.dart`), which
/// exposes the services of `SymphonyCore` to Riverpod.
class ExampleApp extends ConsumerWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Symphony Example',
      debugShowCheckedModeBanner: false,
      theme: exampleLightTheme,
      darkTheme: exampleDarkTheme,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      // A draggable button above every page opens the API inspector.
      builder:
          (context, child) =>
              SymphonyInspectorOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
