import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

/// Renders the `AsyncValue<Result<T>>` exposed by the example's data
/// providers with the package's feedback widgets:
///
/// * loading → [SymphonyLoadingIndicator];
/// * [ResultFailure] (or an unexpected error) → [SymphonyErrorView] with a
///   retry button;
/// * empty data → [emptyBuilder] (usually a [SymphonyEmptyState]);
/// * data → [builder].
///
/// The providers return a `Result` instead of throwing on purpose: Riverpod
/// 3 automatically retries providers that throw (and reports them as
/// loading meanwhile), which would delay error screens by many seconds.
/// Returning a `Result` behaves the same on Riverpod 2 and 3.
///
/// While a successful value is refreshed, the previous data stays visible.
class AsyncResultView<T> extends StatelessWidget {
  /// Creates the view.
  const AsyncResultView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.emptyBuilder,
    this.loadingMessage,
  });

  /// The provider value.
  final AsyncValue<Result<T>> value;

  /// Builds the content for successful data.
  final Widget Function(BuildContext context, T data) builder;

  /// Retries (typically `ref.invalidate(provider)`).
  final VoidCallback? onRetry;

  /// Whether the data is empty (shows [emptyBuilder]).
  final bool Function(T data)? isEmpty;

  /// Builds the empty state.
  final WidgetBuilder? emptyBuilder;

  /// Message of the loading indicator.
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current.isLoading) {
      final previous = current.hasValue ? current.requireValue : null;
      if (previous is ResultSuccess<T>) return _data(context, previous.value);
      return SymphonyLoadingIndicator(message: loadingMessage);
    }
    return current.when(
      loading: () => SymphonyLoadingIndicator(message: loadingMessage),
      error: (error, stackTrace) => SymphonyErrorView(
        failure: error is Failure
            ? error
            : UnexpectedFailure.fromError(error, stackTrace),
        onRetry: onRetry,
      ),
      data: (result) => result.when(
        success: (data) => _data(context, data),
        failure: (failure) => SymphonyErrorView(
          failure: failure,
          onRetry: onRetry,
        ),
      ),
    );
  }

  Widget _data(BuildContext context, T data) {
    final empty = emptyBuilder;
    if (empty != null && (isEmpty?.call(data) ?? false)) return empty(context);
    return builder(context, data);
  }
}
