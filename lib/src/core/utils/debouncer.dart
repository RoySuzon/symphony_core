import 'dart:async';

import 'package:flutter/foundation.dart';

/// Delays an action until calls have stopped for [delay] (trailing-edge
/// debounce).
///
/// Typical use: start a search only once the user stopped typing.
///
/// ```dart
/// final _debouncer = Debouncer(const Duration(milliseconds: 300));
///
/// void _onQueryChanged(String query) {
///   _debouncer.run(() => ref.read(searchProvider.notifier).search(query));
/// }
///
/// @override
/// void dispose() {
///   _debouncer.dispose();
///   super.dispose();
/// }
/// ```
class Debouncer {
  /// Creates a debouncer that runs the latest action once [delay] has elapsed
  /// without another call to [run].
  Debouncer(this.delay)
      : assert(!delay.isNegative, 'delay must not be negative');

  /// Quiet period required before the latest action runs.
  final Duration delay;

  Timer? _timer;
  VoidCallback? _action;
  bool _disposed = false;

  /// Whether an action is scheduled and has not run yet.
  bool get isPending => _timer?.isActive ?? false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Schedules [action] to run once [delay] has elapsed without another call.
  ///
  /// A previously scheduled action that has not run yet is discarded. Calls
  /// made after [dispose] are ignored.
  void run(VoidCallback action) {
    if (_disposed) return;
    _timer?.cancel();
    _action = action;
    _timer = Timer(delay, _fire);
  }

  /// Runs the pending action immediately (for example when a search field is
  /// submitted). Does nothing when no action is pending.
  void flush() {
    if (!isPending) return;
    _timer?.cancel();
    _fire();
  }

  /// Discards the pending action, if any.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _action = null;
  }

  /// Discards the pending action and releases the timer. Subsequent calls to
  /// [run] are ignored.
  void dispose() {
    cancel();
    _disposed = true;
  }

  void _fire() {
    final action = _action;
    _timer = null;
    _action = null;
    action?.call();
  }
}

/// Runs an action at most once per [interval] (leading-edge throttle).
///
/// The first call runs immediately and starts a cooldown of [interval].
/// Calls made during the cooldown are dropped, unless [trailing] is `true`:
/// then the latest of them runs once the cooldown ends (which starts a new
/// cooldown).
///
/// ```dart
/// final _throttler = Throttler(const Duration(seconds: 1));
///
/// FilledButton(
///   onPressed: () => _throttler.run(_submit),
///   child: const Text('Send'),
/// );
/// ```
class Throttler {
  /// Creates a throttler allowing one action per [interval].
  Throttler(this.interval, {this.trailing = false})
      : assert(!interval.isNegative, 'interval must not be negative');

  /// Minimum time between two executed actions.
  final Duration interval;

  /// Whether the latest call made during a cooldown runs when the cooldown
  /// ends. When `false` (the default) such calls are dropped.
  final bool trailing;

  Timer? _cooldown;
  VoidCallback? _trailingAction;
  bool _disposed = false;

  /// Whether a cooldown is active, i.e. a call to [run] would not execute
  /// its action immediately.
  bool get isThrottling => _cooldown?.isActive ?? false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Runs [action] now unless a cooldown is active.
  ///
  /// During a cooldown the action is dropped, or remembered as the trailing
  /// action when [trailing] is `true`. Calls made after [dispose] are ignored.
  void run(VoidCallback action) {
    if (_disposed) return;
    if (isThrottling) {
      if (trailing) _trailingAction = action;
      return;
    }
    _execute(action);
  }

  /// Ends the current cooldown and discards a remembered trailing action.
  void cancel() {
    _cooldown?.cancel();
    _cooldown = null;
    _trailingAction = null;
  }

  /// Cancels the cooldown and releases the timer. Subsequent calls to [run]
  /// are ignored.
  void dispose() {
    cancel();
    _disposed = true;
  }

  void _execute(VoidCallback action) {
    // The cooldown starts before the action runs so that a throwing action,
    // or an action calling run() again, is throttled as well.
    _cooldown = Timer(interval, _onCooldownEnd);
    action();
  }

  void _onCooldownEnd() {
    _cooldown = null;
    final pending = _trailingAction;
    _trailingAction = null;
    if (pending != null && !_disposed) _execute(pending);
  }
}
