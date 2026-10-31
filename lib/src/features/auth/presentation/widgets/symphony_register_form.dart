import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/utils/validators.dart';
import '../../../../ui/widgets/buttons/symphony_button.dart';
import '../../../../ui/widgets/inputs/symphony_password_field.dart';
import '../../../../ui/widgets/inputs/symphony_text_field.dart';
import '../../domain/entities/auth_credentials.dart';
import '../../domain/entities/auth_session.dart';
import '../providers/auth_providers.dart';
import 'auth_inline_message.dart';

/// Registration form: optional name, identifier (e-mail by default),
/// password and password confirmation.
///
/// Calls `AuthController.register`. When the backend signs the new user in,
/// the authentication state becomes authenticated and [onSuccess] receives
/// the session; otherwise (for example e-mail verification is required)
/// [successMessage] is displayed and [onSuccess] receives `null`.
///
/// When the adapter does not support registration, [unsupportedMessage] is
/// displayed instead of the inputs. Every text is overridable.
class SymphonyRegisterForm extends ConsumerStatefulWidget {
  /// Creates a registration form.
  const SymphonyRegisterForm({
    super.key,
    this.showNameField = true,
    this.nameField = 'name',
    this.nameLabel = 'Full name',
    this.nameHint,
    this.nameValidator,
    this.identifierField = 'email',
    this.identifierLabel = 'E-mail',
    this.identifierHint,
    this.identifierIcon = Icons.alternate_email,
    this.identifierKeyboardType = TextInputType.emailAddress,
    this.identifierAutofillHints = const <String>[AutofillHints.email],
    this.identifierValidator,
    this.passwordField = 'password',
    this.passwordLabel = 'Password',
    this.passwordHint,
    this.passwordValidator,
    this.minPasswordLength = 8,
    this.passwordTooShortMessage,
    this.showPasswordStrength = true,
    this.showConfirmPasswordField = true,
    this.confirmPasswordLabel = 'Confirm password',
    this.passwordMismatchMessage = 'Passwords do not match.',
    this.submitLabel = 'Create account',
    this.requiredFieldMessage = 'This field is required.',
    this.invalidEmailMessage = 'Enter a valid e-mail address.',
    this.successMessage =
        'Your account has been created. Check your inbox to activate it.',
    this.unsupportedMessage = 'Registration is not available.',
    this.credentialsBuilder,
    this.extraFields = const <Widget>[],
    this.extraCredentials,
    this.onSuccess,
    this.onFailure,
    this.failureMessageBuilder,
    this.onSignIn,
    this.signInPrompt = 'Already have an account?',
    this.signInLabel = 'Sign in',
  });

  /// Key of the name input.
  static const Key nameInputKey = ValueKey<String>('symphony.register.name');

  /// Key of the identifier input.
  static const Key identifierInputKey = ValueKey<String>(
    'symphony.register.identifier',
  );

  /// Key of the password input.
  static const Key passwordInputKey = ValueKey<String>(
    'symphony.register.password',
  );

  /// Key of the password confirmation input.
  static const Key confirmPasswordInputKey = ValueKey<String>(
    'symphony.register.confirmPassword',
  );

  /// Key of the submit button.
  static const Key submitButtonKey = ValueKey<String>(
    'symphony.register.submit',
  );

  /// Whether the name input is displayed.
  final bool showNameField;

  /// Credentials field receiving the name (default credentials).
  final String nameField;

  /// Label of the name input.
  final String nameLabel;

  /// Placeholder of the name input.
  final String? nameHint;

  /// Validator of the name input. Defaults to a required field.
  final FormFieldValidator<String>? nameValidator;

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

  /// Credentials field receiving the password.
  final String passwordField;

  /// Label of the password input.
  final String passwordLabel;

  /// Placeholder of the password input.
  final String? passwordHint;

  /// Validator of the password input. Defaults to a required password of at
  /// least [minPasswordLength] characters.
  final FormFieldValidator<String>? passwordValidator;

  /// Minimum length enforced by the default password validator.
  final int minPasswordLength;

  /// Message of the default minimum length validator.
  final String? passwordTooShortMessage;

  /// Displays a strength meter below the password input.
  final bool showPasswordStrength;

  /// Whether the password confirmation input is displayed.
  final bool showConfirmPasswordField;

  /// Label of the password confirmation input.
  final String confirmPasswordLabel;

  /// Error displayed when the confirmation differs from the password.
  final String passwordMismatchMessage;

  /// Label of the submit button.
  final String submitLabel;

  /// Message of the default "required" validators.
  final String requiredFieldMessage;

  /// Message of the default e-mail validator.
  final String invalidEmailMessage;

  /// Displayed when the account was created but the user is not signed in.
  final String successMessage;

  /// Displayed instead of the inputs when registration is unsupported.
  final String unsupportedMessage;

  /// Builds the credentials from the trimmed identifier, the password and
  /// the trimmed name (`null` when the name input is hidden or empty).
  /// Defaults to `{identifierField: ..., passwordField: ..., nameField: ...}`.
  final AuthCredentials Function(
    String identifier,
    String password,
    String? name,
  )?
  credentialsBuilder;

  /// Additional inputs displayed after the password inputs (terms of use,
  /// phone number...). Their values are added with [extraCredentials].
  final List<Widget> extraFields;

  /// Values merged into the credentials when the form is submitted.
  final Map<String, Object?> Function()? extraCredentials;

  /// Called after a successful registration with the new session, or `null`
  /// when the backend did not sign the user in.
  final ValueChanged<AuthSession?>? onSuccess;

  /// Called after a failed registration.
  final ValueChanged<Failure>? onFailure;

  /// Converts a failure into the text displayed above the form. Defaults to
  /// `failure.message`.
  final String Function(Failure failure)? failureMessageBuilder;

  /// Opens the sign-in screen. The link is hidden when `null`.
  final VoidCallback? onSignIn;

  /// Text displayed before the sign-in link.
  final String signInPrompt;

  /// Label of the sign-in link.
  final String signInLabel;

  @override
  ConsumerState<SymphonyRegisterForm> createState() =>
      _SymphonyRegisterFormState();
}

class _SymphonyRegisterFormState extends ConsumerState<SymphonyRegisterForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _submitting = false;
  bool _registered = false;
  Failure? _failure;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
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

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _failure = null;
      _registered = false;
      _fieldErrors = const <String, String>{};
    });
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    final trimmedName = _nameController.text.trim();
    final name =
        widget.showNameField && trimmedName.isNotEmpty ? trimmedName : null;
    var credentials =
        widget.credentialsBuilder?.call(identifier, password, name) ??
        AuthCredentials(<String, Object?>{
          widget.identifierField: identifier,
          widget.passwordField: password,
          if (name != null) widget.nameField: name,
        });
    final extra = widget.extraCredentials?.call();
    if (extra != null && extra.isNotEmpty) {
      credentials = credentials.merge(extra);
    }
    final onSuccess = widget.onSuccess;
    final onFailure = widget.onFailure;

    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .register(credentials);

    switch (result) {
      case ResultSuccess<AuthSession?>(:final value):
        if (value != null) TextInput.finishAutofillContext();
        if (mounted) {
          setState(() {
            _submitting = false;
            _registered = value == null;
          });
          if (value == null) {
            _passwordController.clear();
            _confirmController.clear();
          }
        }
        onSuccess?.call(value);
      case ResultFailure<AuthSession?>(:final failure):
        if (mounted) {
          setState(() {
            _submitting = false;
            _failure = failure;
            _fieldErrors = authFieldErrors(failure);
          });
        }
        onFailure?.call(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider.notifier);
    if (!controller.supportsRegistration) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AuthInlineMessage(
            message: widget.unsupportedMessage,
            tone: AuthMessageTone.info,
          ),
          ..._signInLink(),
        ],
      );
    }

    final banner = authBannerMessage(
      _failure,
      visibleFields: <String>{
        if (widget.showNameField) widget.nameField,
        widget.identifierField,
        widget.passwordField,
      },
      messageBuilder: widget.failureMessageBuilder,
    );
    final passwordValidator =
        widget.passwordValidator ??
        SymphonyValidators.compose(<FormFieldValidator<String>>[
          SymphonyValidators.required(message: widget.requiredFieldMessage),
          SymphonyValidators.minLength(
            widget.minPasswordLength,
            message: widget.passwordTooShortMessage,
          ),
        ]);

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
            if (_registered) ...<Widget>[
              AuthInlineMessage(
                message: widget.successMessage,
                tone: AuthMessageTone.success,
              ),
              const SizedBox(height: 16),
            ],
            if (widget.showNameField) ...<Widget>[
              SymphonyTextField(
                key: SymphonyRegisterForm.nameInputKey,
                controller: _nameController,
                label: widget.nameLabel,
                hint: widget.nameHint,
                prefixIcon: Icons.person_outline,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                validator:
                    widget.nameValidator ??
                    SymphonyValidators.required(
                      message: widget.requiredFieldMessage,
                    ),
                errorText: _fieldErrors[widget.nameField],
                enabled: !_submitting,
                onChanged: (_) => _clearFieldError(widget.nameField),
              ),
              const SizedBox(height: 16),
            ],
            SymphonyTextField(
              key: SymphonyRegisterForm.identifierInputKey,
              controller: _identifierController,
              label: widget.identifierLabel,
              hint: widget.identifierHint,
              prefixIcon: widget.identifierIcon,
              keyboardType: widget.identifierKeyboardType,
              textInputAction: TextInputAction.next,
              autofillHints: widget.identifierAutofillHints,
              validator:
                  widget.identifierValidator ??
                  SymphonyValidators.compose(<FormFieldValidator<String>>[
                    SymphonyValidators.required(
                      message: widget.requiredFieldMessage,
                    ),
                    SymphonyValidators.email(
                      message: widget.invalidEmailMessage,
                    ),
                  ]),
              errorText: _fieldErrors[widget.identifierField],
              enabled: !_submitting,
              onChanged: (_) => _clearFieldError(widget.identifierField),
            ),
            const SizedBox(height: 16),
            SymphonyPasswordField(
              key: SymphonyRegisterForm.passwordInputKey,
              controller: _passwordController,
              label: widget.passwordLabel,
              hint: widget.passwordHint,
              validator: passwordValidator,
              errorText: _fieldErrors[widget.passwordField],
              enabled: !_submitting,
              autofillHints: const <String>[AutofillHints.newPassword],
              showStrengthIndicator: widget.showPasswordStrength,
              textInputAction:
                  widget.showConfirmPasswordField
                      ? TextInputAction.next
                      : TextInputAction.done,
              onChanged: (_) => _clearFieldError(widget.passwordField),
              onSubmitted:
                  widget.showConfirmPasswordField ? null : (_) => _submit(),
            ),
            if (widget.showConfirmPasswordField) ...<Widget>[
              const SizedBox(height: 16),
              SymphonyPasswordField(
                key: SymphonyRegisterForm.confirmPasswordInputKey,
                controller: _confirmController,
                label: widget.confirmPasswordLabel,
                enabled: !_submitting,
                autofillHints: const <String>[AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                validator:
                    SymphonyValidators.compose(<FormFieldValidator<String>>[
                      SymphonyValidators.required(
                        message: widget.requiredFieldMessage,
                      ),
                      SymphonyValidators.match(
                        () => _passwordController.text,
                        message: widget.passwordMismatchMessage,
                      ),
                    ]),
                onSubmitted: (_) => _submit(),
              ),
            ],
            for (final field in widget.extraFields) ...<Widget>[
              const SizedBox(height: 16),
              field,
            ],
            const SizedBox(height: 24),
            SymphonyButton(
              key: SymphonyRegisterForm.submitButtonKey,
              label: widget.submitLabel,
              onPressed: _submitting ? null : _submit,
              isLoading: _submitting,
              expanded: true,
              size: SymphonyButtonSize.large,
            ),
            ..._signInLink(),
          ],
        ),
      ),
    );
  }

  List<Widget> _signInLink() {
    final onSignIn = widget.onSignIn;
    if (onSignIn == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: <Widget>[
          Text(widget.signInPrompt),
          SymphonyButton(
            label: widget.signInLabel,
            onPressed: _submitting ? null : onSignIn,
            variant: SymphonyButtonVariant.text,
            size: SymphonyButtonSize.small,
          ),
        ],
      ),
    ];
  }
}
