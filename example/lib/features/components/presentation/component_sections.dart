import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/widgets/app_widgets.dart';

/// `SymphonyButton` variants, sizes, icons, loading and disabled states,
/// plus `SymphonyIconButton`.
class ButtonsSection extends StatefulWidget {
  /// Creates the section.
  const ButtonsSection({super.key});

  @override
  State<ButtonsSection> createState() => _ButtonsSectionState();
}

class _ButtonsSectionState extends State<ButtonsSection> {
  bool _loading = false;

  Future<void> _simulate() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Buttons',
      subtitle: 'SymphonyButton · SymphonyIconButton',
      icon: Icons.smart_button_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Loading'),
          Switch(
            value: _loading,
            onChanged: (value) => setState(() => _loading = value),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: SymphonySpacing.sm,
            runSpacing: SymphonySpacing.sm,
            children: <Widget>[
              for (final variant in SymphonyButtonVariant.values)
                SymphonyButton(
                  label: variant.name.capitalize(),
                  variant: variant,
                  isLoading: _loading,
                  onPressed: () {},
                ),
            ],
          ),
          const SizedBox(height: SymphonySpacing.lg),
          Wrap(
            spacing: SymphonySpacing.sm,
            runSpacing: SymphonySpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final size in SymphonyButtonSize.values)
                SymphonyButton(
                  label:
                      '${size.name.capitalize()} (${size.minHeight.round()})',
                  size: size,
                  icon: Icons.bolt,
                  isLoading: _loading,
                  onPressed: () {},
                ),
              const SymphonyButton(label: 'Disabled', onPressed: null),
              SymphonyButton(
                label: 'Trailing icon',
                trailingIcon: Icons.arrow_forward,
                variant: SymphonyButtonVariant.outlined,
                tooltip: 'Buttons can have tooltips',
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: SymphonySpacing.lg),
          SymphonyButton(
            label: 'Expanded · simulate a 2 s request',
            icon: Icons.cloud_sync_outlined,
            expanded: true,
            isLoading: _loading,
            onPressed: _simulate,
          ),
          const SizedBox(height: SymphonySpacing.lg),
          Wrap(
            spacing: SymphonySpacing.sm,
            children: <Widget>[
              for (final variant in SymphonyIconButtonVariant.values)
                SymphonyIconButton(
                  icon: Icons.favorite_border,
                  tooltip: 'Icon button (${variant.name})',
                  variant: variant,
                  isLoading: _loading,
                  onPressed: () {},
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Text fields with `SymphonyValidators`, and the password field with its
/// strength meter.
class InputsSection extends StatefulWidget {
  /// Creates the section.
  const InputsSection({super.key});

  @override
  State<InputsSection> createState() => _InputsSectionState();
}

class _InputsSectionState extends State<InputsSection> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();
  PasswordStrengthResult? _strength;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _validate() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (valid) SymphonySnackbar.success(context, 'Everything looks valid.');
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength;
    return SectionCard(
      title: 'Inputs',
      subtitle: 'SymphonyTextField · SymphonyPasswordField · '
          'SymphonyValidators',
      icon: Icons.edit_note_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SymphonyTextField(
              label: 'Full name',
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              validator: SymphonyValidators.compose(
                <FormFieldValidator<String>>[
                  SymphonyValidators.required(),
                  SymphonyValidators.minLength(3),
                ],
              ),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            SymphonyTextField(
              label: 'E-mail',
              hint: 'name@company.com',
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              validator: SymphonyValidators.compose(
                <FormFieldValidator<String>>[
                  SymphonyValidators.required(),
                  SymphonyValidators.email(),
                ],
              ),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            SymphonyTextField(
              label: 'Phone',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              helperText: 'Optional — validated only when filled in',
              validator: (value) => value == null || value.isEmpty
                  ? null
                  : SymphonyValidators.phone()(value),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            SymphonyTextField(
              label: 'Amount',
              prefixText: r'$ ',
              suffixText: 'USD',
              keyboardType: TextInputType.number,
              validator: SymphonyValidators.numeric(),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            SymphonyPasswordField(
              controller: _password,
              label: 'Password',
              helperText: 'Try "password", "Zebracat9" and "Zebra-cat9-Moon"',
              showStrengthIndicator: true,
              onStrengthChanged: (result) => setState(() => _strength = result),
              validator: SymphonyValidators.minLength(8),
            ),
            if (strength != null) ...<Widget>[
              const SizedBox(height: SymphonySpacing.xs),
              Text(
                'Score ${strength.score}/100 · ${strength.strength.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: SymphonySpacing.lg),
            SymphonyPasswordField(
              label: 'Confirm password',
              validator: SymphonyValidators.match(
                () => _password.text,
                message: 'Passwords do not match.',
              ),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SymphonyButton(
                label: 'Validate form',
                icon: Icons.rule,
                onPressed: _validate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `SymphonyDialogs`: confirm, alert, prompt and loading dialogs.
class DialogsSection extends StatelessWidget {
  /// Creates the section.
  const DialogsSection({super.key});

  Future<void> _confirm(BuildContext context,
      {required bool destructive}) async {
    final confirmed = await SymphonyDialogs.confirm(
      context,
      title: destructive ? 'Delete the project?' : 'Publish the changes?',
      message: destructive
          ? 'This cannot be undone.'
          : 'Your team will be notified.',
      confirmLabel: destructive ? 'Delete' : 'Publish',
      destructive: destructive,
      icon: destructive ? Icons.delete_outline : Icons.publish_outlined,
    );
    if (context.mounted) {
      SymphonySnackbar.info(context, confirmed ? 'Confirmed' : 'Cancelled');
    }
  }

  Future<void> _prompt(BuildContext context) async {
    final name = await SymphonyDialogs.prompt(
      context,
      title: 'Rename the board',
      label: 'Board name',
      initialValue: 'Q4 roadmap',
      confirmLabel: 'Rename',
      maxLength: 30,
      validator: SymphonyValidators.required(message: 'A name is required.'),
    );
    if (name != null && context.mounted) {
      SymphonySnackbar.success(context, 'Renamed to "$name".');
    }
  }

  Future<void> _loading(BuildContext context) async {
    final handle = SymphonyDialogs.showLoading(
      context,
      message: 'Syncing…',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    handle.close();
  }

  Future<void> _runWithLoading(BuildContext context) async {
    final total = await SymphonyDialogs.runWithLoading(
      context,
      () => Future<int>.delayed(const Duration(milliseconds: 1500), () => 42),
      message: 'Computing…',
    );
    if (context.mounted) {
      await SymphonyDialogs.alert(
        context,
        title: 'Done',
        message: 'runWithLoading returned $total.',
        icon: Icons.check_circle_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Dialogs',
      subtitle: 'SymphonyDialogs',
      icon: Icons.chat_bubble_outline,
      child: Wrap(
        spacing: SymphonySpacing.sm,
        runSpacing: SymphonySpacing.sm,
        children: <Widget>[
          SymphonyButton(
            label: 'Confirm',
            variant: SymphonyButtonVariant.secondary,
            onPressed: () => _confirm(context, destructive: false),
          ),
          SymphonyButton(
            label: 'Destructive confirm',
            variant: SymphonyButtonVariant.danger,
            onPressed: () => _confirm(context, destructive: true),
          ),
          SymphonyButton(
            label: 'Alert',
            variant: SymphonyButtonVariant.outlined,
            onPressed: () => SymphonyDialogs.alert(
              context,
              title: 'Heads up',
              message: 'Alerts have a single button.',
              icon: Icons.info_outline,
            ),
          ),
          SymphonyButton(
            label: 'Prompt',
            variant: SymphonyButtonVariant.outlined,
            onPressed: () => _prompt(context),
          ),
          SymphonyButton(
            label: 'Loading (2 s)',
            variant: SymphonyButtonVariant.text,
            onPressed: () => _loading(context),
          ),
          SymphonyButton(
            label: 'runWithLoading',
            variant: SymphonyButtonVariant.text,
            onPressed: () => _runWithLoading(context),
          ),
        ],
      ),
    );
  }
}

/// `SymphonySnackbar`: every type, with an action, from a `Failure`.
class SnackbarsSection extends StatelessWidget {
  /// Creates the section.
  const SnackbarsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Snackbars',
      subtitle: 'SymphonySnackbar',
      icon: Icons.notifications_none,
      child: Wrap(
        spacing: SymphonySpacing.sm,
        runSpacing: SymphonySpacing.sm,
        children: <Widget>[
          for (final type in SymphonySnackbarType.values)
            SymphonyButton(
              label: type.name.capitalize(),
              icon: SymphonySnackbar.iconFor(type),
              variant: SymphonyButtonVariant.outlined,
              size: SymphonyButtonSize.small,
              onPressed: () => SymphonySnackbar.show(
                context,
                'This is a ${type.name} message.',
                type: type,
              ),
            ),
          SymphonyButton(
            label: 'With action',
            size: SymphonyButtonSize.small,
            variant: SymphonyButtonVariant.secondary,
            onPressed: () => SymphonySnackbar.success(
              context,
              'Order archived.',
              actionLabel: 'Undo',
              onAction: () => SymphonySnackbar.info(context, 'Restored.'),
            ),
          ),
          SymphonyButton(
            label: 'From a Failure',
            size: SymphonyButtonSize.small,
            variant: SymphonyButtonVariant.secondary,
            onPressed: () => SymphonySnackbar.showFailure(
              context,
              const TimeoutFailure(),
            ),
          ),
        ],
      ),
    );
  }
}

/// `SymphonyLoadingOverlay`, `SymphonyLoadingIndicator`,
/// `SymphonyEmptyState` and `SymphonyErrorView`.
class FeedbackSection extends StatefulWidget {
  /// Creates the section.
  const FeedbackSection({super.key});

  @override
  State<FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends State<FeedbackSection> {
  static const List<(String, Failure)> _failures = <(String, Failure)>[
    ('Network', NetworkFailure()),
    ('Timeout', TimeoutFailure()),
    ('Unauthorized', UnauthorizedFailure()),
    ('Forbidden', ForbiddenFailure()),
    ('Not found', NotFoundFailure()),
    (
      'Server',
      ServerFailure('The server is having a bad day.', statusCode: 503),
    ),
  ];

  bool _overlay = false;
  int _failure = 0;

  Future<void> _showOverlay() async {
    setState(() => _overlay = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _overlay = false);
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failures[_failure].$2;
    return SectionCard(
      title: 'Feedback',
      subtitle: 'Loading overlay · loading indicator · empty & error states',
      icon: Icons.feedback_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SymphonyLoadingOverlay(
            isLoading: _overlay,
            message: 'Saving…',
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(SymphonySpacing.lg),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'SymphonyLoadingOverlay blocks this card while a '
                        'task runs and keeps its state.',
                      ),
                    ),
                    const SizedBox(width: SymphonySpacing.md),
                    SymphonyButton(
                      label: 'Run',
                      size: SymphonyButtonSize.small,
                      onPressed: _showOverlay,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              SymphonyLoadingIndicator(size: 28),
              SymphonyLoadingIndicator(size: 28, adaptive: true),
              SymphonyLoadingIndicator(message: 'With a message', size: 28),
            ],
          ),
          const SizedBox(height: SymphonySpacing.lg),
          const SymphonyEmptyState(
            title: 'Compact empty state',
            message: 'Fits inside cards and lists.',
            icon: Icons.inbox_outlined,
            compact: true,
          ),
          const SizedBox(height: SymphonySpacing.lg),
          SizedBox(
            height: 260,
            child: SymphonyEmptyState(
              title: 'No projects yet',
              message: 'Full empty state with an action.',
              icon: Icons.folder_open_outlined,
              actionLabel: 'Create a project',
              actionIcon: Icons.add,
              onAction: () => SymphonySnackbar.info(context, 'Action tapped'),
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          Wrap(
            spacing: SymphonySpacing.sm,
            runSpacing: SymphonySpacing.sm,
            children: <Widget>[
              for (var index = 0; index < _failures.length; index++)
                ChoiceChip(
                  label: Text(_failures[index].$1),
                  selected: index == _failure,
                  onSelected: (_) => setState(() => _failure = index),
                ),
            ],
          ),
          const SizedBox(height: SymphonySpacing.md),
          SymphonyErrorView(
            failure: failure,
            compact: true,
            onRetry: () => SymphonySnackbar.info(context, 'Retry tapped'),
          ),
          const SizedBox(height: SymphonySpacing.md),
          SizedBox(
            height: 300,
            child: SymphonyErrorView(
              failure: failure,
              onRetry: () => SymphonySnackbar.info(context, 'Retry tapped'),
            ),
          ),
        ],
      ),
    );
  }
}

/// `ResponsiveLayout`, `ResponsiveBuilder`, `ResponsiveValue` and the
/// responsive `BuildContext` extension.
class ResponsiveSection extends StatelessWidget {
  /// Creates the section.
  const ResponsiveSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const columns = ResponsiveValue<int>(
      compact: 1,
      medium: 2,
      expanded: 3,
      large: 4,
    );
    Widget panel(String label, Color color, Color onColor) => Container(
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: SymphonyRadius.of(context).mediumBorderRadius,
          ),
          child: Text(label, style: TextStyle(color: onColor)),
        );

    return SectionCard(
      title: 'Responsive layout',
      subtitle: 'Resize the window to see the layouts change',
      icon: Icons.devices_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Screen: ${context.screenSizeClass.name} · '
            'ResponsiveValue → ${columns.resolve(context)} column(s)',
          ),
          const SizedBox(height: SymphonySpacing.md),
          ResponsiveLayout(
            compact: panel(
              'ResponsiveLayout: compact',
              scheme.primaryContainer,
              scheme.onPrimaryContainer,
            ),
            medium: panel(
              'ResponsiveLayout: medium',
              scheme.secondaryContainer,
              scheme.onSecondaryContainer,
            ),
            expanded: panel(
              'ResponsiveLayout: expanded',
              scheme.tertiaryContainer,
              scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: SymphonySpacing.md),
          ResponsiveBuilder(
            builder: (context, sizeClass, constraints) {
              final count = responsiveColumns(
                constraints.maxWidth,
                minTileWidth: 140,
                spacing: SymphonySpacing.sm,
                maxColumns: 6,
              );
              final width =
                  (constraints.maxWidth - SymphonySpacing.sm * (count - 1)) /
                      count;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'ResponsiveBuilder: ${sizeClass.name}, '
                    '${constraints.maxWidth.round()} px → $count columns',
                  ),
                  const SizedBox(height: SymphonySpacing.sm),
                  Wrap(
                    spacing: SymphonySpacing.sm,
                    runSpacing: SymphonySpacing.sm,
                    children: <Widget>[
                      for (var i = 0; i < 6; i++)
                        SizedBox(
                          width: width,
                          child: panel(
                            'Tile ${i + 1}',
                            scheme.primary.withAlpha(30 + i * 25),
                            scheme.onSurface,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Routing helpers: the error screen of unknown locations.
class RoutingSection extends StatelessWidget {
  /// Creates the section.
  const RoutingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Routing',
      subtitle: 'SymphonyRouteErrorScreen for unknown locations',
      icon: Icons.alt_route,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SymphonyButton(
          label: 'Open /does-not-exist',
          icon: Icons.explore_off_outlined,
          variant: SymphonyButtonVariant.outlined,
          onPressed: () => context.go('/does-not-exist'),
        ),
      ),
    );
  }
}
