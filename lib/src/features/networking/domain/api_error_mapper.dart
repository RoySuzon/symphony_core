import '../../../core/error/failure.dart';

/// Converts low level networking errors (typically `DioException`) into
/// [Failure]s.
///
/// Provide a custom implementation to parse project specific error payloads
/// (error codes, field errors...) without touching any repository.
abstract class ApiErrorMapper {
  /// Allows subclasses to have const constructors.
  const ApiErrorMapper();

  /// Maps [error] to a [Failure]. Must never throw.
  Failure map(Object error, StackTrace stackTrace);
}
