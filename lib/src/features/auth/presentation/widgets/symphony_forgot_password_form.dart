import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/utils/validators.dart';
import '../../../../ui/widgets/buttons/symphony_button.dart';
import '../../../../ui/widgets/inputs/symphony_password_field.dart';
import '../../../../ui/widgets/inputs/symphony_text_field.dart';
import '../../domain/entities/auth_credentials.dart';
import '../providers/auth_providers.dart';
import 'auth_inline_message.dart';

enum _RecoveryStep { request, confirm, done }

/// Password recovery form.
///
/// 1. The user enters an identifier (e-mail by default) and the form calls
///    `AuthController.requestPasswordReset`.
/// 2. With [enableConfirmStep] the form then asks for the received code and
///    a new password and calls `AuthController.confirmPasswordReset`.
///    Without it, recovery is expected to finish outside the app (for
///    example through a link sent by e-mail) and [requestSuccessMessage] is
///    displayed.
///
/// When the adapter does not support password recovery,
/// [unsupportedMessage] is displayed instead. Every text is overridable.
class SymphonyForgotPasswordForm extends ConsumerStatefulWidget {
  /// Creates a password recovery form.
  const SymphonyForgotPasswordForm({
    super.key,
    this.identifierField = 'email',
    this.identifierLabel = 'E-mail',
    this.identifierHint,
    this.identifierIcon = Icons.alternate_email,
    this.identifierKeyboardType = TextInputType.emailAddress,
    this.identifierAutofillHints = const <String>[AutofillHints.email],
    this.identifierValidator,
    this.initialIdentifier,
    this.description = 'Enter the e-mail address of your account and we will '
        'send you instructions to reset your password.',
    this.submitLabel = 'Send instructions',
    this.requestSuccessMessage = 'If an account exists for this address, you '
        'will receive password reset instructions shortly.',
    this.requestCredentialsBuilder,
    this.enableConfirmStep = false,
    this.confirmDescription =
        'Enter the code you received and choose a new password.',
    this.codeField = 'code',
    this.codeLabel = 'Verification code',
    this.codeHint,
    this.codeKeyboardType = TextInputType.number,
    this.codeValidator,
    this.newPasswordField = 'password',
    this.newPasswordLabel = 'New password',
    this.newPasswordValidator,
    this.minPasswordLength = 8,
    this.passwordTooShortMessage,
    this.showConfirmPasswordField = true,
    this.confirmPasswordLabel = 'Confirm new password',
    this.passwordMismatchMessage = 'Passwords do not match.',
    this.confirmSubmitLabel = 'Reset password',
    this.confirmSuccessMessage =
        'Your password has been reset. You can now sign in.',
    this.resendLabel = 'Resend code',
    this.confirmCredentialsBuilder,
    this.requiredFieldMessage = 'This field is required.',
    this.invalidEmailMessage = 'Enter a valid e-mail address.',
    this.unsupportedMessage = 'Password recovery is not available.',
    this.onRequestSent,
    this.onCompleted,
    this.onFailure,
    this.failureMessageBuilder,
    this.onBackToSignIn,
    this.backToSignInLabel = 'Back to sign in',
  });

  /// Key of the identifier input.
  static const Key identifierInputKey =
      ValueKey<String>('symphony.recovery.identifier');

  /// Key of the request button.
  static const Key requestButtonKey =
      ValueKey<String>('symphony.recovery.request');

  /// Key of the code input (confirmation step).
  static const Key codeInputKey = ValueKey<String>('symphony.recovery.code');

  /// Key of the new password input (confirmation step).
  static const Key newPasswordInputKey =
      ValueKey<String>('symphony.recovery.newPassword');

  /// Key of the new password confirmation input (confirmation step).
  static const Key confirmPasswordInputKey =
      ValueKey<String>('symphony.recovery.confirmPassword');

  /// Key of the confirmation button (confirmation step).
  static const Key confirmButtonKey =
      ValueKey<String>('symphony.recovery.confirm');

  /// Credentials field receiving the identifier.
  final String identifierField;

  /// Label of the identifier input.
  final String identifierLabel;

  /// Placeholder of the identifier input.
  final String? identifierHint;

  /// Leading icon of the identifier input.
  final IconData? identifierIcon;

  /// Keyboard of the identifier input.
  final TextInputType identifierKeyboardType;

  /// Autofill hints of the identifier input.
  final Iterable<String> identifierAutofillHints;

  /// Validator of the identifier input. Defaults to a required e-mail
  /// address.
  final FormFieldValidator<String>? identifierValidator;

  /// Initial identifier (for example the e-mail typed on the sign-in form).
  final String? initialIdentifier;

  /// Text displayed above the identifier input. `null` hides it.
  final String? description;

  /// Label of the request button.
  final String submitLabel;

  /// Displayed after a successful request.
  final String requestSuccessMessage;

  /// Builds the request credentials from the trimmed identifier. Defaults to
  /// `{identifierField: identifier}`.
  final AuthCredentials Function(String identifier)? requestCredentialsBuilder;

  /// Whether the form continues with a code + new password step.
  final bool enableConfirmStep;

  /// Text displayed above the confirmation inputs. `null` hides it.
  final String? confirmDescription;

  /// Credentials field receiving the code (default confirm credentials).
  final String codeField;

  /// Label of the code input.
  final String codeLabel;

  /// Placeholder of the code input.
  final String? codeHint;

  /// Keyboard of the code input.
  final TextInputType codeKeyboardType;

  /// Validator of the code input. Defaults to a required field.
  final FormFieldValidator<String>? codeValidator;

  /// Credentials field receiving the new password.
  final String newPasswordField;

  /// Label of the new password input.
  final String newPasswordLabel;

  /// Validator of the new password input. Defaults to a required password of
  /// at least [minPasswordLength] characters.
  final FormFieldValidator<String>? newPasswordValidator;

  /// Minimum length enforced by the default new password validator.
  final int minPasswordLength;

  /// Message of the default minimum length validator.
  final String? passwordTooShortMessage;

  /// Whether the new password confirmation input is displayed.
  final bool showConfirmPasswordField;

  /// Label of the new password confirmation input.
  final String confirmPasswordLabel;

  /// Error displayed when the confirmation differs from the new password.
  final String passwordMismatchMessage;

  /// Label of the confirmation button.
  final String confirmSubmitLabel;

  /// Displayed after the password was reset.
  final String confirmSuccessMessage;

  /// Label of the "resend code" link of the confirmation step.
  final String resendLabel;

  /// Builds the confirmation credentials from the identifier, the trimmed
  /// code and the new password. Defaults to
  /// `{identifierField: ..., codeField: ..., newPasswordField: ...}`.
  final AuthCredentials Function(
    String identifier,
    String code,
    String newPassword,
  )? confirmCredentialsBuilder;

  /// Message of the default "required" validators.
  final String requiredFieldMessage;

  /// Message of the default e-mail validator.
  final String invalidEmailMessage;

  /// Displayed instead of the form when recovery is unsupported.
  final String unsupportedMessage;

  /// Called with the identifier after a successful request.
  final ValueChanged<String>? onRequestSent;

  /// Called after the password was reset (confirmation step).
  final VoidCallback? onCompleted;

  /// Called when a request or a confirmation fails.
  final ValueChanged<Failure>? onFailure;

  /// Converts a failure into the text displayed above the form. Defaults to
  /// `failure.message`.
  final String Function(Failure failure)? failureMessageBuilder;

  /// Returns to the sign-in screen. The link is hidden when `null`.
  final VoidCallback? onBackToSignIn;

  /// Label of the "back to sign in" link.
  final String backToSignInLabel;

  @override
  ConsumerState<SymphonyForgotPasswordForm> createState() =>
      _SymphonyForgotPasswordFormState();
}

class _SymphonyForgotPasswordFormState
    extends ConsumerState<SymphonyForgotPasswordForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifierController =
      TextEditingController(text: widget.initialIdentifier);
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  _RecoveryStep _step = _RecoveryStep.request;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _submitting = false;
  String? _successMessage;
  Failure? _failure;
  Map<String, String> _fieldErrors = const <String, String>{};
  String _identifier = '';

  @override
  void dispose() {
    _identifierController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() {
      _fieldErrors = Map<String, String>.of(_fieldErrors)..remove(field);
    });
  }

  bool _validate() {
    setState(() {
      _failure = null;
      _fieldErrors = const <String, String>{};
    });
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return false;
    }
    return true;
  }

  void _showFailure(Failure failure) {
    setState(() {
      _submitting = false;
      _successMessage = null;
      _failure = failure;
      _fieldErrors = authFieldErrors(failure);
    });
  }

  Future<void> _request({bool resend = false}) async {
    if (_submitting) return;
    if (!resend && !_validate()) return;
    final identifier = resend ? _identifier : _identifierController.text.trim();
    final credentials = widget.requestCredentialsBuilder?.call(identifier) ??
        AuthCredentials(<String, Object?>{
          widget.identifierField: identifier,
        });
    final onRequestSent = widget.onRequestSent;
    final onFailure = widget.onFailure;

    setState(() {
      _submitting = true;
      _failure = null;
    });
    final result = await ref
        .read(authControllerProvider.notifier)
        .requestPasswordReset(credentials);

    switch (result) {
      case ResultSuccess<void>():
        if (mounted) {
          setState(() {
            _submitting = false;
            _identifier = identifier;
            _successMessage = widget.requestSuccessMessage;
            _autovalidateMode = AutovalidateMode.disabled;
            _step = widget.enableConfirmStep
                ? _RecoveryStep.confirm
                : _RecoveryStep.done;
          });
        }
        onRequestSent?.call(identifier);
      case ResultFailure<void>(:final failure):
        if (mounted) _showFailure(failure);
        onFailure?.call(failure);
    }
  }

  Future<void> _confirm() async {
    if (_submitting || !_validate()) return;
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final credentials =
        widget.confirmCredentialsBuilder?.call(_identifier, code, password) ??
            AuthCredentials(<String, Object?>{
              widget.identifierField: _identifier,
              widget.codeField: code,
              widget.newPasswordField: password,
            });
    final onCompleted = widget.onCompleted;
    final onFailure = widget.onFailure;

    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .confirmPasswordReset(credentials);

    switch (result) {
      case ResultSuccess<void>():
        if (mounted) {
          setState(() {
            _submitting = false;
            _successMessage = widget.confirmSuccessMessage;
            _step = _RecoveryStep.done;
          });
        }
        onCompleted?.call();
      case ResultFailure<void>(:final failure):
        if (mounted) _showFailure(failure);
        onFailure?.call(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider.notifier);
    if (!controller.supportsPasswordRecovery) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AuthInlineMessage(
            message: widget.unsupportedMessage,
            tone: AuthMessageTone.info,
          ),
          ..._backLink(),
        ],
      );
    }

    final banner = authBannerMessage(
      _failure,
      visibleFields: switch (_step) {
        _RecoveryStep.request => <String>{widget.identifierField},
        _RecoveryStep.confirm => <String>{
            widget.codeField,
            widget.newPasswordField,
          },
        _RecoveryStep.done => const <String>{},
      },
      messageBuilder: widget.failureMessageBuilder,
    );
    final successMessage = _successMessage;

    return Form(
      key: _formKey,
      autovalidateMode: _autovalidateMode,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (banner != null) ...<Widget>[
              AuthInlineMessage(message: banner),
              const SizedBox(height: 16),
            ],
            if (successMessage != null) ...<Widget>[
              AuthInlineMessage(
                message: successMessage,
                tone: AuthMessageTone.success,
              ),
              const SizedBox(height: 16),
            ],
            ...switch (_step) {
              _RecoveryStep.request => _requestStep(context),
              _RecoveryStep.confirm => _confirmStep(context),
              _RecoveryStep.done => const <Widget>[],
            },
            ..._backLink(),
          ],
        ),
      ),
    );
  }

  List<Widget> _description(BuildContext context, String? text) {
    if (text == null || text.isEmpty) return const <Widget>[];
    final theme = Theme.of(context);
    return <Widget>[
      Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _requestStep(BuildContext context) {
    return <Widget>[
      ..._description(context, widget.description),
      SymphonyTextField(
        key: SymphonyForgotPasswordForm.identifierInputKey,
        controller: _identifierController,
        label: widget.identifierLabel,
        hint: widget.identifierHint,
        prefixIcon: widget.identifierIcon,
        keyboardType: widget.identifierKeyboardType,
        textInputAction: TextInputAction.done,
        autofillHints: widget.identifierAutofillHints,
        validator: widget.identifierValidator ??
            SymphonyValidators.compose(<FormFieldValidator<String>>[
              SymphonyValidators.required(message: widget.requiredFieldMessage),
              SymphonyValidators.email(message: widget.invalidEmailMessage),
            ]),
        errorText: _fieldErrors[widget.identifierField],
        enabled: !_submitting,
        onChanged: (_) => _clearFieldError(widget.identifierField),
        onSubmitted: (_) => _request(),
      ),
      const SizedBox(height: 24),
      SymphonyButton(
        key: SymphonyForgotPasswordForm.requestButtonKey,
        label: widget.submitLabel,
        onPressed: _submitting ? null : _request,
        isLoading: _submitting,
        expanded: true,
        size: SymphonyButtonSize.large,
      ),
    ];
  }

  List<Widget> _confirmStep(BuildContext context) {
    return <Widget>[
      ..._description(context, widget.confirmDescription),
      SymphonyTextField(
        key: SymphonyForgotPasswordForm.codeInputKey,
        controller: _codeController,
        label: widget.codeLabel,
        hint: widget.codeHint,
        prefixIcon: Icons.pin_outlined,
        keyboardType: widget.codeKeyboardType,
        textInputAction: TextInputAction.next,
        autofillHints: const <String>[AutofillHints.oneTimeCode],
        validator: widget.codeValidator ??
            SymphonyValidators.required(message: widget.requiredFieldMessage),
        errorText: _fieldErrors[widget.codeField],
        enabled: !_submitting,
        onChanged: (_) => _clearFieldError(widget.codeField),
      ),
      const SizedBox(height: 16),
      SymphonyPasswordField(
        key: SymphonyForgotPasswordForm.newPasswordInputKey,
        controller: _passwordController,
        label: widget.newPasswordLabel,
        validator: widget.newPasswordValidator ??
            SymphonyValidators.compose(<FormFieldValidator<String>>[
              SymphonyValidators.required(message: widget.requiredFieldMessage),
              SymphonyValidators.minLength(
                widget.minPasswordLength,
                message: widget.passwordTooShortMessage,
              ),
            ]),
        errorText: _fieldErrors[widget.newPasswordField],
        enabled: !_submitting,
        autofillHints: const <String>[AutofillHints.newPassword],
        showStrengthIndicator: true,
        textInputAction: widget.showConfirmPasswordField
            ? TextInputAction.next
            : TextInputAction.done,
        onChanged: (_) => _clearFieldError(widget.newPasswordField),
        onSubmitted: widget.showConfirmPasswordField ? null : (_) => _confirm(),
      ),
      if (widget.showConfirmPasswordField) ...<Widget>[
        const SizedBox(height: 16),
        SymphonyPasswordField(
          key: SymphonyForgotPasswordForm.confirmPasswordInputKey,
          controller: _confirmController,
          label: widget.confirmPasswordLabel,
          enabled: !_submitting,
          autofillHints: const <String>[AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          validator: SymphonyValidators.compose(<FormFieldValidator<String>>[
            SymphonyValidators.required(message: widget.requiredFieldMessage),
            SymphonyValidators.match(
              () => _passwordController.text,
              message: widget.passwordMismatchMessage,
            ),
          ]),
          onSubmitted: (_) => _confirm(),
        ),
      ],
      const SizedBox(height: 24),
      SymphonyButton(
        key: SymphonyForgotPasswordForm.confirmButtonKey,
        label: widget.confirmSubmitLabel,
        onPressed: _submitting ? null : _confirm,
        isLoading: _submitting,
        expanded: true,
        size: SymphonyButtonSize.large,
      ),
      const SizedBox(height: 8),
      Align(
        child: SymphonyButton(
          label: widget.resendLabel,
          onPressed: _submitting ? null : () => _request(resend: true),
          variant: SymphonyButtonVariant.text,
          size: SymphonyButtonSize.small,
        ),
      ),
    ];
  }

  List<Widget> _backLink() {
    final onBack = widget.onBackToSignIn;
    if (onBack == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 16),
      Align(
        child: SymphonyButton(
          label: widget.backToSignInLabel,
          onPressed: _submitting ? null : onBack,
          variant: SymphonyButtonVariant.text,
          size: SymphonyButtonSize.small,
          icon: Icons.arrow_back,
        ),
      ),
    ];
  }
}
