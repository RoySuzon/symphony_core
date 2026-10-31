// Internal helpers of the storage module. Not exported by the module barrel.
import 'dart:async';

import '../../../core/error/failure.dart';

/// Runs [body] and converts any error that is not already a [Failure] into
/// a [StorageFailure] with [message] and [code].
///
/// Synchronous throws of [body] are converted as well, so plugin calls that
/// validate their arguments eagerly are covered too.
Future<T> guardStorage<T>(
  Future<T> Function() body, {
  required String message,
  required String code,
}) async {
  try {
    return await body();
  } on Failure {
    rethrow;
  } on Object catch (error, stackTrace) {
    throw StorageFailure(
      message,
      code: code,
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

/// Runs asynchronous tasks one at a time, in the order they were submitted.
///
/// Used to make read-modify-write sequences atomic within one store.
final class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  /// Schedules [task] after every previously scheduled task and completes
  /// with its outcome. A failing task does not prevent the next ones.
  Future<R> run<R>(Future<R> Function() task) {
    final completer = Completer<R>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// Fan-out of the `watchAll` streams of a store.
///
/// Each stream first receives an initial snapshot (or error) handed to
/// [start] / [startWithError], then every snapshot passed to [emit].
final class StoreWatchers<T> {
  final Set<MultiStreamController<List<T>>> _listening =
      <MultiStreamController<List<T>>>{};
  final Set<MultiStreamController<List<T>>> _started =
      <MultiStreamController<List<T>>>{};

  /// Whether at least one stream waits for change notifications.
  bool get hasActiveWatchers => _started.isNotEmpty;

  /// Creates a stream that can be listened to any number of times. Each
  /// listener triggers [onListen], which must eventually call [start] or
  /// [startWithError] with the listener's controller.
  Stream<List<T>> watch(
    void Function(MultiStreamController<List<T>> controller) onListen,
  ) {
    return Stream<List<T>>.multi((controller) {
      _listening.add(controller);
      controller.onCancel = () {
        _listening.remove(controller);
        _started.remove(controller);
      };
      onListen(controller);
    });
  }

  /// Sends [snapshot] to [controller] and subscribes it to [emit].
  ///
  /// Does nothing when the listener was cancelled or closed meanwhile.
  void start(MultiStreamController<List<T>> controller, List<T> snapshot) {
    if (!_listening.contains(controller)) return;
    controller.add(snapshot);
    _started.add(controller);
  }

  /// Sends [error] to [controller] and subscribes it to [emit].
  ///
  /// Does nothing when the listener was cancelled or closed meanwhile.
  void startWithError(
    MultiStreamController<List<T>> controller,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_listening.contains(controller)) return;
    controller.addError(error, stackTrace);
    _started.add(controller);
  }

  /// Sends [snapshot] to every started stream.
  void emit(List<T> snapshot) {
    for (final controller in _started.toList()) {
      controller.add(snapshot);
    }
  }

  /// Sends [error] to every started stream.
  void emitError(Object error, StackTrace stackTrace) {
    for (final controller in _started.toList()) {
      controller.addError(error, stackTrace);
    }
  }

  /// Completes every stream, started or not.
  ///
  /// Does not wait for the done events to be delivered, so a paused listener
  /// cannot block the caller.
  void closeAll() {
    final controllers = _listening.toList();
    _listening.clear();
    _started.clear();
    for (final controller in controllers) {
      unawaited(controller.close());
    }
  }
}
