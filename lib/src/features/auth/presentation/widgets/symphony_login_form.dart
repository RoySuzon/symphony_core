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

/// Sign-in form: identifier (e-mail by default) and password fields, a submit
/// button with a loading state, failure messages and optional "forgot
/// password" / "create account" links.
///
/// The form only collects input: it calls `AuthController.login` and reports
/// the outcome through [onSuccess] / [onFailure]. Navigation is left to the
/// application (router redirects or the callbacks). Every text is
/// overridable for localization.
///
/// Field errors of a [ValidationFailure] (`fieldErrors`) are displayed under
/// the matching field ([identifierField], [passwordField]); other failures
/// are displayed above the form.
///
/// ```dart
/// SymphonyLoginForm(
///   identifierField: 'username',
///   identifierLabel: 'Username',
///   identifierKeyboardType: TextInputType.text,
///   identifierValidator: SymphonyValidators.required(),
///   onForgotPassword: () => context.push('/forgot-password'),
///   onRegister: () => context.push('/register'),
/// );
/// ```
class SymphonyLoginForm extends ConsumerStatefulWidget {
  /// Creates a sign-in form.
  const SymphonyLoginForm({
    super.key,
    this.identifierField = 'email',
    this.passwordField = 'password',
    this.identifierLabel = 'E-mail',
    this.identifierHint,
    this.identifierIcon = Icons.alternate_email,
    this.identifierKeyboardType = TextInputType.emailAddress,
    this.identifierAutofillHints = const <String>[AutofillHints.email],
    this.identifierValidator,
    this.initialIdentifier,
    this.passwordLabel = 'Password',
    this.passwordHint,
    this.passwordValidator,
    this.submitLabel = 'Sign in',
    this.requiredFieldMessage = 'This field is required.',
    this.invalidEmailMessage = 'Enter a valid e-mail address.',
    this.credentialsBuilder,
    this.extraFields = const <Widget>[],
    this.extraCredentials,
    this.onSuccess,
    this.onFailure,
    this.failureMessageBuilder,
    this.onForgotPassword,
    this.forgotPasswordLabel = 'Forgot password?',
    this.onRegister,
    this.registerPrompt = "Don't have an account?",
    this.registerLabel = 'Create one',
    this.autofocus = false,
  });

  /// Key of the identifier input (useful in widget tests).
  static const Key identifierInputKey = ValueKey<String>(
    'symphony.login.identifier',
  );

  /// Key of the password input.
  static const Key passwordInputKey = ValueKey<String>(
    'symphony.login.password',
  );

  /// Key of the submit button.
  static const Key submitButtonKey = ValueKey<String>('symphony.login.submit');

  /// Credentials field receiving the identifier (default credentials) and
  /// the field whose server-side errors are shown under the identifier.
  final String identifierField;

  /// Credentials field receiving the password. See [identifierField].
  final String passwordField;

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
  /// address (built with [requiredFieldMessage] and [invalidEmailMessage]);
  /// pass `SymphonyValidators.required()` for usernames or phone numbers.
  final FormFieldValidator<String>? identifierValidator;

  /// Initial identifier (for example the last signed-in e-mail).
  final String? initialIdentifier;

  /// Label of the password input.
  final String passwordLabel;

  /// Placeholder of the password input.
  final String? passwordHint;

  /// Validator of the password input. Defaults to a required field.
  final FormFieldValidator<String>? passwordValidator;

  /// Label of the submit button.
  final String submitLabel;

  /// Message of the default "required" validators.
  final String requiredFieldMessage;

  /// Message of the default e-mail validator.
  final String invalidEmailMessage;

  /// Builds the credentials from the (trimmed) identifier and the password.
  /// Defaults to `{identifierField: identifier, passwordField: password}`,
  /// which equals `AuthCredentials.emailPassword` with the default fields.
  final AuthCredentials Function(String identifier, String password)?
  credentialsBuilder;

  /// Additional inputs displayed after the password (tenant picker,
  /// "remember me"...). Their values are added with [extraCredentials].
  final List<Widget> extraFields;

  /// Values merged into the credentials when the form is submitted.
  final Map<String, Object?> Function()? extraCredentials;

  /// Called after a successful sign-in (even when a route redirect already
  /// removed the form from the tree).
  final ValueChanged<AuthSession>? onSuccess;

  /// Called after a failed sign-in.
  final ValueChanged<Failure>? onFailure;

  /// Converts a failure into the text displayed above the form (for
  /// localization). Defaults to `failure.message`.
  final String Function(Failure failure)? failureMessageBuilder;

  /// Opens the password recovery flow. The link is shown only when this is
  /// set **and** the adapter supports password recovery.
  final VoidCallback? onForgotPassword;

  /// Label of the "forgot password" link.
  final String forgotPasswordLabel;

  /// Opens the registration flow. The link is shown only when this is set
  /// **and** the adapter supports registration.
  final VoidCallback? onRegister;

  /// Text displayed before the registration link.
  final String registerPrompt;

  /// Label of the registration link.
  final String registerLabel;

  /// Focuses the identifier input on first build.
  final bool autofocus;

  @override
  ConsumerState<SymphonyLoginForm> createState() => _SymphonyLoginFormState();
}

class _SymphonyLoginFormState extends ConsumerState<SymphonyLoginForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifierController =
      TextEditingController(text: widget.initialIdentifier);
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();

  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _submitting = false;
  Failure? _failure;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  FormFieldValidator<String> get _identifierValidator =>
      widget.identifierValidator ??
      SymphonyValidators.compose(<FormFieldValidator<String>>[
        SymphonyValidators.required(message: widget.requiredFieldMessage),
        SymphonyValidators.email(message: widget.invalidEmailMessage),
      ]);

  FormFieldValidator<String> get _passwordValidator =>
      widget.passwordValidator ??
      SymphonyValidators.required(message: widget.requiredFieldMessage);

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
      _fieldErrors = const <String, String>{};
    });
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    var credentials =
        widget.credentialsBuilder?.call(identifier, password) ??
        AuthCredentials(<String, Object?>{
          widget.identifierField: identifier,
          widget.passwordField: password,
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
        .login(credentials);

    switch (result) {
      case ResultSuccess<AuthSession>(:final value):
        TextInput.finishAutofillContext();
        if (mounted) setState(() => _submitting = false);
        onSuccess?.call(value);
      case ResultFailure<AuthSession>(:final failure):
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
    final showForgotPassword =
        widget.onForgotPassword != null && controller.supportsPasswordRecovery;
    final showRegister =
        widget.onRegister != null && controller.supportsRegistration;
    final banner = authBannerMessage(
      _failure,
      visibleFields: <String>{widget.identifierField, widget.passwordField},
      messageBuilder: widget.failureMessageBuilder,
    );

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
            SymphonyTextField(
              key: SymphonyLoginForm.identifierInputKey,
              controller: _identifierController,
              label: widget.identifierLabel,
              hint: widget.identifierHint,
              prefixIcon: widget.identifierIcon,
              keyboardType: widget.identifierKeyboardType,
              textInputAction: TextInputAction.next,
              autofillHints: widget.identifierAutofillHints,
              validator: _identifierValidator,
              errorText: _fieldErrors[widget.identifierField],
              enabled: !_submitting,
              autofocus: widget.autofocus,
              onChanged: (_) => _clearFieldError(widget.identifierField),
              onSubmitted: (_) => _passwordFocusNode.requestFocus(),
            ),
            const SizedBox(height: 16),
            SymphonyPasswordField(
              key: SymphonyLoginForm.passwordInputKey,
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              label: widget.passwordLabel,
              hint: widget.passwordHint,
              validator: _passwordValidator,
              errorText: _fieldErrors[widget.passwordField],
              enabled: !_submitting,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearFieldError(widget.passwordField),
              onSubmitted: (_) => _submit(),
            ),
            if (showForgotPassword) ...<Widget>[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SymphonyButton(
                  label: widget.forgotPasswordLabel,
                  onPressed: _submitting ? null : widget.onForgotPassword,
                  variant: SymphonyButtonVariant.text,
                  size: SymphonyButtonSize.small,
                ),
              ),
            ],
            for (final field in widget.extraFields) ...<Widget>[
              const SizedBox(height: 16),
              field,
            ],
            const SizedBox(height: 24),
            SymphonyButton(
              key: SymphonyLoginForm.submitButtonKey,
              label: widget.submitLabel,
              onPressed: _submitting ? null : _submit,
              isLoading: _submitting,
              expanded: true,
              size: SymphonyButtonSize.large,
            ),
            if (showRegister) ...<Widget>[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: <Widget>[
                  Text(widget.registerPrompt),
                  SymphonyButton(
                    label: widget.registerLabel,
                    onPressed: _submitting ? null : widget.onRegister,
                    variant: SymphonyButtonVariant.text,
                    size: SymphonyButtonSize.small,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
