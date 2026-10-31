import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/access_context.dart';
import '../../../ui/widgets/feedback/symphony_empty_state.dart';
import '../domain/dashboard_item.dart';
import '../domain/dashboard_menu.dart';
import 'dashboard_grid.dart';
import 'dashboard_navigation.dart';
import 'dashboard_providers.dart';

/// Opens the submenu of the group identified by [groupPath] (ids of nested
/// groups, top level first). [context] is the context of the tapped tile.
typedef DashboardSubmenuOpener =
    void Function(BuildContext context, List<String> groupPath);

/// A full-screen page displaying the children of a dashboard group.
///
/// `SymphonyDashboard` pushes it with `Navigator.push` when its
/// `submenuPresentation` is `DashboardSubmenuPresentation.page`. It can also
/// be used directly, for example as the screen of a `GoRoute` that
/// deep-links into a submenu:
///
/// ```dart
/// GoRoute(
///   path: '/modules/sales',
///   builder: (context, state) =>
///       const SymphonyDashboardSubmenuPage(groupPath: ['sales']),
/// );
/// ```
///
/// The page filters the menu like the dashboard (from [items] or
/// `dashboardItemsProvider`, and [accessContext] or `accessContextProvider`)
/// and reacts to access changes: children appear or disappear, and when the
/// group itself is no longer available the page closes itself (it pops when
/// it is the current route, or is removed from the navigator when it is a
/// pageless route below other routes). A page that cannot be closed (the
/// first route) displays the empty state instead.
///
/// It requires a `ProviderScope` ancestor.
class SymphonyDashboardSubmenuPage extends ConsumerStatefulWidget {
  /// Creates a page displaying the children of the group at [groupPath].
  const SymphonyDashboardSubmenuPage({
    super.key,
    required this.groupPath,
    this.items,
    this.accessContext,
    this.title,
    this.maxCrossAxisExtent = 180,
    this.crossAxisCount,
    this.childAspectRatio = 1,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(16),
    this.physics,
    this.tileBuilder,
    this.onItemSelected,
    this.onOpenSubmenu,
    this.emptyState,
    this.emptyTitle = 'No modules available',
    this.emptyMessage,
  });

  /// Ids of the nested groups leading to the displayed group, top level
  /// first. `['sales', 'sales.reports']` displays the children of the
  /// `sales.reports` group located inside the `sales` group.
  final List<String> groupPath;

  /// The whole menu (top level). Defaults to `dashboardItemsProvider`.
  final List<DashboardItem>? items;

  /// Access used to filter the menu. Defaults to `accessContextProvider`.
  final AccessContext? accessContext;

  /// Title of the app bar. Defaults to the group's label.
  final Widget? title;

  /// Maximum tile width when [crossAxisCount] is `null`.
  final double maxCrossAxisExtent;

  /// Fixed number of columns. Overrides [maxCrossAxisExtent].
  final int? crossAxisCount;

  /// Width / height ratio of the tiles.
  final double childAspectRatio;

  /// Gap between tiles.
  final double spacing;

  /// Padding around the grid.
  final EdgeInsetsGeometry padding;

  /// Scroll physics of the grid.
  final ScrollPhysics? physics;

  /// Builds custom tiles. Defaults to `SymphonyDashboardTile`.
  final DashboardTileBuilder? tileBuilder;

  /// Called when a leaf is tapped, instead of navigating to its destination.
  final ValueChanged<DashboardItem>? onItemSelected;

  /// Opens nested groups. Defaults to pushing another
  /// [SymphonyDashboardSubmenuPage] with the same configuration.
  final DashboardSubmenuOpener? onOpenSubmenu;

  /// Widget displayed when the group is not available. Defaults to a
  /// `SymphonyEmptyState` built from [emptyTitle] and [emptyMessage].
  final Widget? emptyState;

  /// Title of the default empty state.
  final String emptyTitle;

  /// Message of the default empty state.
  final String? emptyMessage;

  @override
  ConsumerState<SymphonyDashboardSubmenuPage> createState() =>
      _SymphonyDashboardSubmenuPageState();
}

class _SymphonyDashboardSubmenuPageState
    extends ConsumerState<SymphonyDashboardSubmenuPage> {
  ModalRoute<Object?>? _route;
  String? _lastTitle;
  bool _dismissScheduled = false;

  @override
  Widget build(BuildContext context) {
    _route = ModalRoute.of(context);
    final visible = watchVisibleDashboardItems(
      ref,
      items: widget.items,
      accessContext: widget.accessContext,
    );
    final groupPath = widget.groupPath;
    final resolved = DashboardMenu.resolveSubmenuPath(visible, groupPath);
    final DashboardItem? group =
        groupPath.isNotEmpty && resolved.length == groupPath.length
            ? resolved.last
            : null;
    if (group != null) {
      _lastTitle = group.label;
    } else {
      _scheduleDismiss();
    }

    return Scaffold(
      appBar: AppBar(
        title: widget.title ?? Text(group?.label ?? _lastTitle ?? ''),
      ),
      body: SymphonyDashboardGrid(
        items: group?.children ?? const <DashboardItem>[],
        onItemTap: _handleTap,
        tileBuilder: widget.tileBuilder,
        emptyState:
            widget.emptyState ??
            SymphonyEmptyState(
              title: widget.emptyTitle,
              message: widget.emptyMessage,
              icon: Icons.dashboard_outlined,
            ),
        maxCrossAxisExtent: widget.maxCrossAxisExtent,
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
        spacing: widget.spacing,
        padding: widget.padding,
        physics: widget.physics,
      ),
    );
  }

  /// Closes the page after the current frame because its group is no longer
  /// available.
  void _scheduleDismiss() {
    if (_dismissScheduled) return;
    _dismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dismissScheduled = false;
      final route = _route;
      if (!mounted || route == null || !route.isActive) return;
      final navigator = route.navigator;
      if (navigator == null) return;
      if (route.isCurrent) {
        unawaited(navigator.maybePop());
      } else if (route.settings is! Page<Object?>) {
        // Page-based routes belong to the router; only pageless routes can be
        // removed imperatively.
        navigator.removeRoute(route);
      }
    });
  }

  void _handleTap(BuildContext tileContext, DashboardItem item) {
    final onItemSelected = widget.onItemSelected;
    final action = DashboardMenu.resolveTapAction(
      item,
      hasSelectionHandler: onItemSelected != null,
    );
    switch (action) {
      case DashboardTapAction.none:
        return;
      case DashboardTapAction.custom:
        item.onTap?.call(tileContext);
      case DashboardTapAction.openSubmenu:
        final groupPath = <String>[...widget.groupPath, item.id];
        final opener = widget.onOpenSubmenu;
        if (opener != null) {
          opener(tileContext, groupPath);
        } else {
          _pushNestedPage(tileContext, groupPath);
        }
      case DashboardTapAction.select:
        onItemSelected?.call(item);
      case DashboardTapAction.navigate:
        navigateToDashboardItem(tileContext, item);
    }
  }

  void _pushNestedPage(BuildContext context, List<String> groupPath) {
    final config = widget;
    final page = SymphonyDashboardSubmenuPage(
      groupPath: groupPath,
      items: config.items,
      accessContext: config.accessContext,
      maxCrossAxisExtent: config.maxCrossAxisExtent,
      crossAxisCount: config.crossAxisCount,
      childAspectRatio: config.childAspectRatio,
      spacing: config.spacing,
      padding: config.padding,
      physics: config.physics,
      tileBuilder: config.tileBuilder,
      onItemSelected: config.onItemSelected,
      emptyState: config.emptyState,
      emptyTitle: config.emptyTitle,
      emptyMessage: config.emptyMessage,
    );
    unawaited(
      Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page)),
    );
  }
}
