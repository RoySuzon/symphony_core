import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/symphony_radius.dart';
import '../../theme/symphony_spacing.dart';
import '../buttons/symphony_button.dart';
import '../feedback/symphony_loading_indicator.dart';
import '../inputs/symphony_text_field.dart';

/// Ready-made Material 3 dialogs: confirmation, alert, text prompt and a
/// blocking loading dialog.
///
/// Every user facing string has an overridable default so applications can
/// localize them.
///
/// ```dart
/// final confirmed = await SymphonyDialogs.confirm(
///   context,
///   title: 'Delete project?',
///   message: 'This cannot be undone.',
///   confirmLabel: 'Delete',
///   destructive: true,
/// );
/// if (!confirmed) return;
/// await SymphonyDialogs.runWithLoading(
///   context,
///   () => repository.delete(id),
///   message: 'Deleting…',
/// );
/// ```
abstract final class SymphonyDialogs {
  /// Asks the user to confirm an action.
  ///
  /// Completes with `true` when [confirmLabel] is pressed and `false` when
  /// [cancelLabel] is pressed or the dialog is dismissed. [destructive]
  /// renders the confirm button (and the optional [icon]) with the theme
  /// error colours.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: icon == null
              ? null
              : Icon(icon, color: destructive ? scheme.error : null),
          title: Text(title),
          content: message == null ? null : Text(message),
          actions: <Widget>[
            SymphonyButton(
              label: cancelLabel,
              variant: SymphonyButtonVariant.text,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            SymphonyButton(
              label: confirmLabel,
              variant: destructive
                  ? SymphonyButtonVariant.danger
                  : SymphonyButtonVariant.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Shows an informational dialog with a single [buttonLabel] button.
  ///
  /// Completes when the dialog is closed.
  static Future<void> alert(
    BuildContext context, {
    required String title,
    String? message,
    String buttonLabel = 'OK',
    IconData? icon,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) => AlertDialog(
        icon: icon == null ? null : Icon(icon),
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: <Widget>[
          SymphonyButton(
            label: buttonLabel,
            variant: SymphonyButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  /// Asks the user to enter a text.
  ///
  /// Completes with the entered text when [confirmLabel] is pressed (or the
  /// keyboard action is triggered) and [validator] accepts it, or with `null`
  /// when the dialog is cancelled or dismissed.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? message,
    String? initialValue,
    String? label,
    String? hint,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    FormFieldValidator<String>? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    int? maxLength,
    int maxLines = 1,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (_) => _SymphonyPromptDialog(
        title: title,
        message: message,
        initialValue: initialValue,
        label: label,
        hint: hint,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        validator: validator,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        obscureText: obscureText,
        maxLength: maxLength,
        maxLines: maxLines,
      ),
    );
  }

  /// Shows a non-dismissible loading dialog and returns a handle to close it.
  ///
  /// The dialog cannot be dismissed by tapping the barrier; call
  /// [SymphonyLoadingDialogHandle.close] when the work is done (it is safe to
  /// call several times). Prefer [runWithLoading], which always closes the
  /// dialog. [semanticsLabel] defaults to [message], or `'Loading'`.
  static SymphonyLoadingDialogHandle showLoading(
    BuildContext context, {
    String? message,
    String? semanticsLabel,
    bool useRootNavigator = true,
    Color? barrierColor,
  }) {
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final route = DialogRoute<void>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: false,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (_) => _SymphonyLoadingDialog(
        message: message,
        semanticsLabel: semanticsLabel,
      ),
    );
    final handle = SymphonyLoadingDialogHandle._(route);
    unawaited(navigator.push(route));
    return handle;
  }

  /// Runs [task] while a loading dialog is displayed and returns its result.
  ///
  /// The dialog is closed whether [task] completes or throws; errors are
  /// rethrown to the caller.
  static Future<T> runWithLoading<T>(
    BuildContext context,
    Future<T> Function() task, {
    String? message,
    String? semanticsLabel,
    bool useRootNavigator = true,
  }) async {
    final handle = showLoading(
      context,
      message: message,
      semanticsLabel: semanticsLabel,
      useRootNavigator: useRootNavigator,
    );
    try {
      final result = await task();
      return result;
    } finally {
      handle.close();
    }
  }
}

/// Controls a loading dialog opened with [SymphonyDialogs.showLoading].
class SymphonyLoadingDialogHandle {
  SymphonyLoadingDialogHandle._(this._route) {
    // The route can also be removed by the system back button.
    unawaited(_route.popped.whenComplete(_markClosed));
  }

  final Route<void> _route;
  final Completer<void> _closed = Completer<void>();

  /// Whether the dialog is still displayed.
  bool get isOpen => !_closed.isCompleted;

  /// Completes once the dialog has been closed (by [close] or by the user
  /// navigating back).
  Future<void> get closed => _closed.future;

  /// Closes the dialog. Does nothing if it is already closed.
  void close() {
    if (!isOpen) return;
    _markClosed();
    final navigator = _route.navigator;
    if (navigator == null) return;
    if (_route.isCurrent) {
      navigator.pop();
    } else if (_route.isActive) {
      navigator.removeRoute(_route);
    }
  }

  void _markClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

class _SymphonyLoadingDialog extends StatelessWidget {
  const _SymphonyLoadingDialog({
    required this.message,
    required this.semanticsLabel,
  });

  final String? message;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = SymphonyRadius.of(context);
    return Center(
      child: Padding(
        padding: SymphonySpacing.allXl,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 6,
          shadowColor: theme.colorScheme.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: radius.extraLargeBorderRadius,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 320),
            child: Padding(
              padding: SymphonySpacing.allXl,
              // IntrinsicWidth shrink-wraps the centered indicator so the
              // card is only as wide as its content.
              child: IntrinsicWidth(
                child: SymphonyLoadingIndicator(
                  message: message,
                  size: 32,
                  semanticsLabel: semanticsLabel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SymphonyPromptDialog extends StatefulWidget {
  const _SymphonyPromptDialog({
    required this.title,
    required this.message,
    required this.initialValue,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.validator,
    required this.keyboardType,
    required this.textCapitalization,
    required this.obscureText,
    required this.maxLength,
    required this.maxLines,
  });

  final String title;
  final String? message;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String confirmLabel;
  final String cancelLabel;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final int? maxLength;
  final int maxLines;

  @override
  State<_SymphonyPromptDialog> createState() => _SymphonyPromptDialogState();
}

class _SymphonyPromptDialogState extends State<_SymphonyPromptDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_submitted) setState(() => _submitted = true);
    final form = _formKey.currentState;
    if (form != null && !form.validate()) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (message != null) ...<Widget>[
              Text(message),
              const SizedBox(height: SymphonySpacing.lg),
            ],
            SymphonyTextField(
              controller: _controller,
              label: widget.label,
              hint: widget.hint,
              autofocus: true,
              validator: widget.validator,
              keyboardType: widget.keyboardType,
              textCapitalization: widget.textCapitalization,
              obscureText: widget.obscureText,
              maxLength: widget.maxLength,
              maxLines: widget.maxLines,
              textInputAction: widget.maxLines == 1
                  ? TextInputAction.done
                  : TextInputAction.newline,
              onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        SymphonyButton(
          label: widget.cancelLabel,
          variant: SymphonyButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SymphonyButton(
          label: widget.confirmLabel,
          onPressed: _submit,
        ),
      ],
    );
  }
}
