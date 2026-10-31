import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/access/access_requirement.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Shows [child] only to users satisfying [requirement], [fallback]
/// otherwise.
///
/// Use it for permission-based UI and navigation entries (menu items,
/// buttons, tabs). It rebuilds when the user's access changes (sign-in,
/// sign-out, role or permission updates). It only hides UI: protect the
/// destination routes with `GuardedRoute` as well.
///
/// ```dart
/// AccessGate(
///   requirement: const AccessRequirement(permissions: {'orders.write'}),
///   fallback: const SizedBox.shrink(),
///   child: SymphonyButton(
///     label: 'New order',
///     onPressed: () => context.go('/orders/new'),
///   ),
/// )
/// ```
class AccessGate extends ConsumerWidget {
  /// Creates an access gate.
  const AccessGate({
    super.key,
    required this.requirement,
    required this.child,
    this.fallback,
  });

  /// Rule the current user must satisfy to see [child].
  final AccessRequirement requirement;

  /// Widget shown to allowed users.
  final Widget child;

  /// Widget shown to other users. Defaults to an empty box.
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watchCanAccess(requirement);
    return allowed ? child : fallback ?? const SizedBox.shrink();
  }
}

/// Access checks for widgets using Riverpod.
extension SymphonyAccessWidgetRef on WidgetRef {
  /// Whether the current user satisfies [requirement]. Rebuilds the widget
  /// when the answer changes; call it from `build`.
  bool watchCanAccess(AccessRequirement requirement) => watch(
        accessContextProvider.select(
          (access) => access.satisfies(requirement),
        ),
      );

  /// Whether the current user satisfies [requirement], read once. Use it in
  /// callbacks such as `onPressed`.
  bool readCanAccess(AccessRequirement requirement) =>
      read(accessContextProvider).satisfies(requirement);
}
