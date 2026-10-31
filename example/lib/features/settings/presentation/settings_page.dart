import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/backend/demo_backend.dart';
import '../../../core/backend/demo_backend_providers.dart';
import '../../../core/storage/resilient_key_value_storage.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../domain/settings_entities.dart';
import 'settings_providers.dart';

/// Settings: theme, server environment (runtime base URL switch), API
/// inspector, demo backend developer tools, storage and sign-out.
class SettingsPage extends ConsumerWidget {
  /// Creates the page.
  const SettingsPage({super.key});

  /// Key of the sign-out button (widget tests).
  static const Key signOutButtonKey = ValueKey<String>('settings.signOut');

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authControllerProvider.notifier);
    final confirmed = await SymphonyDialogs.confirm(
      context,
      title: 'Sign out?',
      message: 'Your session will be closed on this device.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout,
    );
    // The router sends the user to the login screen once signed out.
    if (confirmed) await auth.logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider);
    final backend = ref.watch(demoBackendProvider);
    return AppPage(
      title: 'Settings',
      scrollable: true,
      maxWidth: 720,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionCard(
            title: 'Appearance',
            subtitle: 'SymphonyTheme.light / SymphonyTheme.dark',
            icon: Icons.palette_outlined,
            child: SegmentedButton<ThemePreference>(
              segments: const <ButtonSegment<ThemePreference>>[
                ButtonSegment<ThemePreference>(
                  value: ThemePreference.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment<ThemePreference>(
                  value: ThemePreference.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment<ThemePreference>(
                  value: ThemePreference.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: <ThemePreference>{preferences.theme},
              onSelectionChanged:
                  (selection) => ref
                      .read(appPreferencesProvider.notifier)
                      .setTheme(selection.first),
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          const _EnvironmentSection(),
          const SizedBox(height: SymphonySpacing.lg),
          SectionCard(
            title: 'API inspector',
            subtitle:
                'Every request of the ApiClient, with headers, bodies '
                '(sensitive values masked) and cURL export.',
            icon: Icons.manage_search_rounded,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SymphonyButton(
                label: 'Open the API inspector',
                icon: Icons.open_in_new,
                variant: SymphonyButtonVariant.outlined,
                onPressed: () => showApiInspector(context),
              ),
            ),
          ),
          if (backend != null) ...<Widget>[
            const SizedBox(height: SymphonySpacing.lg),
            _DeveloperToolsSection(backend: backend),
          ],
          const SizedBox(height: SymphonySpacing.lg),
          const _StorageSection(),
          const SizedBox(height: SymphonySpacing.lg),
          SectionCard(
            title: 'Account',
            icon: Icons.person_outline,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SymphonyButton(
                key: signOutButtonKey,
                label: 'Sign out',
                icon: Icons.logout,
                variant: SymphonyButtonVariant.danger,
                onPressed: () => _signOut(context, ref),
              ),
            ),
          ),
          const SizedBox(height: SymphonySpacing.xl),
        ],
      ),
    );
  }
}

class _EnvironmentSection extends ConsumerWidget {
  const _EnvironmentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedEnvironmentProvider);
    final client = ref.watch(apiClientProvider);
    final status = ref.watch(serverStatusProvider);
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Server environment',
      subtitle: 'Switched at runtime with apiClient.updateBaseUrl().',
      icon: Icons.dns_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final environment in serverEnvironments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                environment.id == selected.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color:
                    environment.id == selected.id
                        ? theme.colorScheme.primary
                        : null,
              ),
              title: Text(environment.label),
              subtitle: Text(
                '${environment.baseUrl}\n'
                '${environment.description}',
              ),
              isThreeLine: true,
              onTap:
                  environment.id == selected.id
                      ? null
                      : () => ref
                          .read(appPreferencesProvider.notifier)
                          .setEnvironment(environment),
            ),
          const Divider(),
          ValueListenableBuilder<String>(
            valueListenable: client.baseUrlListenable,
            builder:
                (context, baseUrl, child) =>
                    InfoRow(label: 'ApiClient.baseUrl', value: baseUrl),
          ),
          status.when(
            loading: () => const InfoRow(label: 'Status', value: 'Checking…'),
            error:
                (error, stackTrace) =>
                    InfoRow(label: 'Status', value: '$error'),
            data:
                (result) => result.when(
                  success:
                      (value) => Column(
                        children: <Widget>[
                          InfoRow(
                            label: 'Answered by',
                            value: '${value.host} (${value.environment})',
                          ),
                          InfoRow(
                            label: 'Service',
                            value: '${value.service} ${value.version}',
                          ),
                        ],
                      ),
                  failure:
                      (failure) =>
                          InfoRow(label: 'Status', value: failure.message),
                ),
          ),
          const SizedBox(height: SymphonySpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SymphonyButton(
              label: 'Ping the server',
              icon: Icons.network_ping,
              variant: SymphonyButtonVariant.text,
              size: SymphonyButtonSize.small,
              onPressed: () => ref.invalidate(serverStatusProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperToolsSection extends ConsumerWidget {
  const _DeveloperToolsSection({required this.backend});

  final DemoBackend backend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(demoOfflineProvider);
    final session = ref.watch(authControllerProvider).session;
    final expiresAt = session?.tokens.expiresAt;
    return SectionCard(
      title: 'Demo backend tools',
      subtitle:
          'Provoke the situations the core handles for you, then '
          'watch the API inspector.',
      icon: Icons.science_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (expiresAt != null)
            InfoRow(
              label: 'Access token expiry',
              value:
                  '${Formatters.time(expiresAt)} '
                  '(${Formatters.countdown(expiresAt.difference(DateTime.now()))})',
            ),
          const SizedBox(height: SymphonySpacing.sm),
          Wrap(
            spacing: SymphonySpacing.sm,
            runSpacing: SymphonySpacing.sm,
            children: <Widget>[
              SymphonyButton(
                label: 'Expire access token',
                icon: Icons.timer_off_outlined,
                variant: SymphonyButtonVariant.secondary,
                onPressed: () {
                  backend.expireAccessTokens();
                  SymphonySnackbar.info(
                    context,
                    'The next request gets a 401: the ApiClient refreshes the '
                    'token and replays it. Open any module, then the '
                    'inspector.',
                  );
                },
              ),
              SymphonyButton(
                label: 'Revoke sessions',
                icon: Icons.block,
                variant: SymphonyButtonVariant.outlined,
                onPressed: () {
                  backend.revokeSessions();
                  backend.expireAccessTokens();
                  SymphonySnackbar.warning(
                    context,
                    'The next request cannot refresh the session: you will '
                    'be signed out.',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: SymphonySpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Simulate a network outage'),
            subtitle: const Text(
              'Requests fail with a connection error (NetworkFailure).',
            ),
            value: offline,
            onChanged:
                (value) =>
                    ref.read(demoOfflineProvider.notifier).set(offline: value),
          ),
        ],
      ),
    );
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(secureStorageProvider);
    final fallback =
        storage is ResilientKeyValueStorage && storage.isUsingFallback;
    return SectionCard(
      title: 'Storage',
      subtitle: 'Session and preferences go through secureStorageProvider.',
      icon: Icons.lock_outline,
      child: InfoRow(
        label: 'Backend',
        value:
            fallback
                ? 'In memory (secure storage is unavailable on this platform)'
                : storage is ResilientKeyValueStorage
                ? 'Secure storage (flutter_secure_storage)'
                : '${storage.runtimeType}',
      ),
    );
  }
}
