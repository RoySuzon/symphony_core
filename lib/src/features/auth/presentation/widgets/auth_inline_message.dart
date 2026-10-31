// Internal helpers shared by the authentication forms. Not exported from the
// auth barrel.
import 'package:flutter/material.dart';

import '../../../../core/error/failure.dart';

/// Visual tone of an [AuthInlineMessage].
enum AuthMessageTone {
  /// Something went wrong.
  error,

  /// An operation succeeded.
  success,

  /// Neutral information.
  info,
}

/// Compact message box displayed above or below authentication forms.
class AuthInlineMessage extends StatelessWidget {
  /// Creates a message box.
  const AuthInlineMessage({
    super.key,
    required this.message,
    this.tone = AuthMessageTone.error,
  });

  /// Text to display.
  final String message;

  /// Colors and icon of the box.
  final AuthMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground, IconData icon) = switch (tone) {
      AuthMessageTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
      AuthMessageTone.success => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      AuthMessageTone.info => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First error message per field of a [ValidationFailure] (empty for other
/// failures).
Map<String, String> authFieldErrors(Failure failure) {
  if (failure is! ValidationFailure) return const <String, String>{};
  return <String, String>{
    for (final entry in failure.fieldErrors.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.first,
  };
}

/// The message to display for [failure] above a form, or `null` when every
/// error of the failure is already displayed next to one of [visibleFields].
String? authBannerMessage(
  Failure? failure, {
  required Set<String> visibleFields,
  String Function(Failure failure)? messageBuilder,
}) {
  if (failure == null) return null;
  final fieldErrors = authFieldErrors(failure);
  if (fieldErrors.isNotEmpty &&
      fieldErrors.keys.every(visibleFields.contains)) {
    return null;
  }
  return messageBuilder?.call(failure) ?? failure.message;
}
