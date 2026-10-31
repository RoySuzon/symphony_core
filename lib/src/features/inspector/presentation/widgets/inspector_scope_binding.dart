// Internal helper of the inspector widgets; intentionally not exported by the
// module barrel.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/core_providers.dart';
import '../../data/api_inspector.dart';
import '../inspector_providers.dart';

/// Binds a widget to the inspector-related providers of the nearest
/// `ProviderScope` **without requiring one**.
///
/// `ConsumerWidget`s throw when no `ProviderScope` exists, while the
/// inspector widgets must also work with an explicitly passed inspector in
/// apps that do not use Riverpod. This binding looks the container up
/// manually, listens to [apiInspectorProvider] and/or
/// `SymphonyConfig.enableInspector` when asked to, and degrades to `null`
/// values when the scope or the configuration is missing.
class InspectorScopeBinding {
  /// Creates a binding calling [onChanged] whenever a bound value changes.
  InspectorScopeBinding({required this.onChanged});

  /// Called after [inspector] or [configEnabled] changed.
  final VoidCallback onChanged;

  ProviderContainer? _container;
  bool _bindInspector = false;
  bool _bindConfig = false;
  ProviderSubscription<ApiInspector>? _inspectorSubscription;
  ProviderSubscription<bool>? _configSubscription;
  ApiInspector? _inspector;
  bool? _configEnabled;

  /// The inspector of [apiInspectorProvider], when bound and available.
  ApiInspector? get inspector => _inspector;

  /// `SymphonyConfig.enableInspector`, when bound and configured.
  bool? get configEnabled => _configEnabled;

  /// Resolves the container of [context] and (re)binds the requested values.
  ///
  /// Call it from `State.didChangeDependencies` (with [listen] true so the
  /// widget is rebuilt when the scope changes) and from
  /// `State.didUpdateWidget` (with [listen] false) when the requested values
  /// change.
  void update(
    BuildContext context, {
    required bool inspector,
    bool config = false,
    bool listen = true,
  }) {
    final container = _containerOf(context, listen: listen);
    if (identical(container, _container) &&
        inspector == _bindInspector &&
        config == _bindConfig) {
      return;
    }
    _close();
    _container = container;
    _bindInspector = inspector;
    _bindConfig = config;
    if (container == null) return;
    if (inspector) _subscribeInspector(container);
    if (config) _subscribeConfig(container);
  }

  /// Releases every subscription.
  void dispose() {
    _close();
    _container = null;
  }

  /// Reads the shared inspector visible from [context] once, or returns
  /// `null` when there is no `ProviderScope` or no configuration.
  static ApiInspector? read(BuildContext context) {
    final container = _containerOf(context, listen: false);
    if (container == null) return null;
    try {
      return container.read(apiInspectorProvider);
    } on Object {
      return null;
    }
  }

  static ProviderContainer? _containerOf(
    BuildContext context, {
    required bool listen,
  }) {
    try {
      return ProviderScope.containerOf(context, listen: listen);
    } on StateError {
      return null;
    }
  }

  void _subscribeInspector(ProviderContainer container) {
    ProviderSubscription<ApiInspector>? subscription;
    try {
      subscription = container.listen<ApiInspector>(
        apiInspectorProvider,
        (previous, next) {
          _inspector = next;
          onChanged();
        },
        onError: (error, stackTrace) {
          _inspector = null;
          onChanged();
        },
      );
      _inspector = subscription.read();
      _inspectorSubscription = subscription;
    } on Object {
      subscription?.close();
      _inspector = null;
    }
  }

  void _subscribeConfig(ProviderContainer container) {
    ProviderSubscription<bool>? subscription;
    try {
      subscription = container.listen<bool>(
        symphonyConfigProvider.select((config) => config.enableInspector),
        (previous, next) {
          _configEnabled = next;
          onChanged();
        },
        onError: (error, stackTrace) {
          _configEnabled = null;
          onChanged();
        },
      );
      _configEnabled = subscription.read();
      _configSubscription = subscription;
    } on Object {
      subscription?.close();
      _configEnabled = null;
    }
  }

  void _close() {
    _inspectorSubscription?.close();
    _configSubscription?.close();
    _inspectorSubscription = null;
    _configSubscription = null;
    _inspector = null;
    _configEnabled = null;
  }
}

/// Rebuilds [state] safely: immediately, or after the current frame when
/// called while the widget tree is being built.
void rebuildInspectorState(State<StatefulWidget> state, VoidCallback rebuild) {
  if (!state.mounted) return;
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    binding.addPostFrameCallback((_) {
      if (state.mounted) rebuild();
    });
  } else {
    rebuild();
  }
}
