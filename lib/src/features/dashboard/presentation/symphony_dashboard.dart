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
import 'symphony_dashboard_controller.dart';
import 'symphony_dashboard_submenu_page.dart';

/// How a [SymphonyDashboard] displays the children of a group.
enum DashboardSubmenuPresentation {
  /// The grid is replaced in place by the group's children (with a short
  /// cross-fade), under a header showing a back button and a breadcrumb. This
  /// is the default. The opened level can be driven with a
  /// [SymphonyDashboardController].
  inline,

  /// Each group opens a [SymphonyDashboardSubmenuPage] pushed with
  /// `Navigator.push`; the app bar back button and the platform back button
  /// close it.
  page,
}

/// A permission-aware dashboard: a responsive grid of module tiles with
/// nested submenus and GoRouter navigation.
///
/// The application supplies the menu ([items], or `dashboardItemsProvider`)
/// and the package filters it for the current user ([accessContext], or
/// `accessContextProvider`): items whose [DashboardItem.access] is not met are
/// hidden, and groups left without visible children disappear (see
/// [DashboardMenu.filterVisibleItems]). The grid updates as soon as the
/// access changes (sign in/out, new roles or permissions); an opened submenu
/// that is no longer available falls back to the nearest visible level.
///
/// Tapping a tile, in order of precedence (see
/// [DashboardMenu.resolveTapAction]):
/// 1. does nothing when the item is disabled;
/// 2. calls [DashboardItem.onTap] when set;
/// 3. opens the submenu of a group, inline or as a page according to
///    [submenuPresentation];
/// 4. calls [onItemSelected] when set (it replaces the navigation);
/// 5. navigates to [DashboardItem.routeName] (`goNamed`/`pushNamed`) or
///    [DashboardItem.route] (`go`/`push`) with the nearest `GoRouter`.
///    Without GoRouter the route is pushed as a `Navigator` named route; when
///    that is not possible either, the problem is reported with
///    `FlutterError.reportError` instead of crashing (see
///    [navigateToDashboardItem]).
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Dashboard')),
///   body: SymphonyDashboard(
///     items: const [
///       DashboardItem(id: 'orders', label: 'Orders',
///           icon: Icons.receipt_long, routeName: 'orders'),
///       DashboardItem(id: 'admin', label: 'Administration',
///           icon: Icons.admin_panel_settings,
///           access: AccessRequirement(roles: {'admin'}),
///           children: [
///             DashboardItem(id: 'admin.users', label: 'Users',
///                 icon: Icons.group, route: '/admin/users'),
///           ]),
///     ],
///   ),
/// );
/// ```
///
/// The dashboard fills the available height and scrolls; set [shrinkWrap]
/// to embed it in another scroll view. It requires a `ProviderScope`
/// ancestor (always present in apps set up with `SymphonyCore`).
class SymphonyDashboard extends ConsumerStatefulWidget {
  /// Creates a dashboard.
  const SymphonyDashboard({
    super.key,
    this.items,
    this.accessContext,
    this.controller,
    this.title,
    this.header,
    this.maxCrossAxisExtent = 180,
    this.crossAxisCount,
    this.childAspectRatio = 1,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(16),
    this.shrinkWrap = false,
    this.physics,
    this.tileBuilder,
    this.onItemSelected,
    this.submenuPresentation = DashboardSubmenuPresentation.inline,
    this.showBreadcrumbs = true,
    this.transitionDuration = const Duration(milliseconds: 250),
    this.emptyState,
    this.emptyTitle = 'No modules available',
    this.emptyMessage,
    this.backLabel = 'Back',
    this.rootLabel = 'Home',
  })  : assert(maxCrossAxisExtent > 0, 'maxCrossAxisExtent must be positive.'),
        assert(
          crossAxisCount == null || crossAxisCount > 0,
          'crossAxisCount must be positive.',
        ),
        assert(childAspectRatio > 0, 'childAspectRatio must be positive.'),
        assert(spacing >= 0, 'spacing must not be negative.');

  /// The whole menu (top level, with nested children). Defaults to
  /// `dashboardItemsProvider`.
  final List<DashboardItem>? items;

  /// Access used to filter the menu. Defaults to `accessContextProvider`,
  /// which follows the authentication state.
  final AccessContext? accessContext;

  /// Drives the opened inline submenu. When `null`, the dashboard manages it
  /// internally. Ignored with [DashboardSubmenuPresentation.page].
  final SymphonyDashboardController? controller;

  /// Section title displayed above the tiles of the top level (styled with
  /// the theme's `titleLarge`). Inside an inline submenu it is replaced by the
  /// submenu header.
  final Widget? title;

  /// Widget displayed above the grid at every level, for example a welcome
  /// banner. It does not scroll with the tiles and keeps its state while
  /// submenus open and close. It is laid out as is: include your own padding.
  final Widget? header;

  /// Maximum width of a tile when [crossAxisCount] is `null`: the grid uses
  /// as many columns as needed to keep tiles at most this wide.
  final double maxCrossAxisExtent;

  /// Fixed number of columns. Overrides [maxCrossAxisExtent].
  final int? crossAxisCount;

  /// Width / height ratio of the tiles.
  final double childAspectRatio;

  /// Horizontal and vertical gap between tiles.
  final double spacing;

  /// Padding around the grid (and the title or submenu header).
  final EdgeInsetsGeometry padding;

  /// Whether the dashboard sizes itself to its content (for example inside
  /// another scroll view) instead of filling the available height.
  final bool shrinkWrap;

  /// Scroll physics of the grid.
  final ScrollPhysics? physics;

  /// Builds custom tiles. Defaults to `SymphonyDashboardTile`.
  final DashboardTileBuilder? tileBuilder;

  /// Called when a leaf is tapped, instead of navigating to its destination.
  ///
  /// Groups still open their submenu and [DashboardItem.onTap] still takes
  /// precedence. Use it to integrate another navigation solution or to
  /// handle items that have no route.
  final ValueChanged<DashboardItem>? onItemSelected;

  /// How the children of a group are displayed. Defaults to
  /// [DashboardSubmenuPresentation.inline].
  final DashboardSubmenuPresentation submenuPresentation;

  /// Whether the inline submenu header shows the full breadcrumb (each level
  /// tappable) or only the current group's label.
  final bool showBreadcrumbs;

  /// Duration of the cross-fade between inline levels. `Duration.zero`
  /// disables the animation.
  final Duration transitionDuration;

  /// Widget displayed when the user cannot see any item. Defaults to a
  /// `SymphonyEmptyState` built from [emptyTitle] and [emptyMessage].
  final Widget? emptyState;

  /// Title of the default empty state.
  final String emptyTitle;

  /// Message of the default empty state.
  final String? emptyMessage;

  /// Tooltip and semantic label of the inline submenu back button.
  final String backLabel;

  /// Label of the first breadcrumb entry, which returns to the top level.
  final String rootLabel;

  @override
  ConsumerState<SymphonyDashboard> createState() => _SymphonyDashboardState();
}

class _SymphonyDashboardState extends ConsumerState<SymphonyDashboard> {
  SymphonyDashboardController? _internalController;

  /// Latest configuration, listened to by the pushed submenu pages so that
  /// they follow changes of [SymphonyDashboard.items] and
  /// [SymphonyDashboard.accessContext].
  late final ValueNotifier<SymphonyDashboard> _pageConfig;

  List<DashboardItem> _visible = const <DashboardItem>[];
  List<DashboardItem> _openPath = const <DashboardItem>[];
  bool _controllerSyncScheduled = false;
  bool _pageConfigSyncScheduled = false;

  SymphonyDashboardController get _controller =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _pageConfig = ValueNotifier<SymphonyDashboard>(widget);
    if (widget.controller == null) {
      _internalController = SymphonyDashboardController();
    }
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SymphonyDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_handleControllerChanged);
      if (widget.controller == null) {
        _internalController ??= SymphonyDashboardController();
      } else {
        _internalController?.dispose();
        _internalController = null;
      }
      _controller.addListener(_handleControllerChanged);
    }
    _schedulePageConfigSync();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _internalController?.dispose();
    _pageConfig.dispose();
    super.dispose();
  }

  void _handleControllerChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final visible = watchVisibleDashboardItems(
      ref,
      items: widget.items,
      accessContext: widget.accessContext,
    );
    _visible = visible;

    final inline =
        widget.submenuPresentation == DashboardSubmenuPresentation.inline;
    final requestedPath = _controller.path;
    final openPath = inline
        ? DashboardMenu.resolveSubmenuPath(visible, requestedPath)
        : const <DashboardItem>[];
    _openPath = openPath;
    if (inline && openPath.length != requestedPath.length) {
      _scheduleControllerSync();
    }

    final levelKey = 'symphony_dashboard:'
        '${openPath.map((group) => group.id).join('\u001f')}';
    final Widget body = AnimatedSwitcher(
      duration: widget.transitionDuration,
      layoutBuilder: _layoutLevels,
      child: SymphonyDashboardGrid(
        // Gives each level its own scroll offset, restored when returning to
        // it, and makes the switcher animate between levels.
        key: PageStorageKey<String>(levelKey),
        items: openPath.isEmpty ? visible : openPath.last.children,
        onItemTap: _handleTap,
        tileBuilder: widget.tileBuilder,
        header: _buildLevelHeader(context, openPath),
        emptyState: openPath.isEmpty ? _buildEmptyState() : null,
        maxCrossAxisExtent: widget.maxCrossAxisExtent,
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
        spacing: widget.spacing,
        padding: widget.padding,
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
      ),
    );

    final header = widget.header;
    if (header == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: <Widget>[
        header,
        if (widget.shrinkWrap) body else Expanded(child: body),
      ],
    );
  }

  static Widget _layoutLevels(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.topCenter,
      children: <Widget>[
        ...previousChildren,
        if (currentChild != null) currentChild,
      ],
    );
  }

  Widget? _buildLevelHeader(
    BuildContext context,
    List<DashboardItem> openPath,
  ) {
    if (openPath.isNotEmpty) {
      return _SubmenuHeader(
        path: openPath,
        rootLabel: widget.rootLabel,
        backLabel: widget.backLabel,
        showBreadcrumbs: widget.showBreadcrumbs,
        onSelectDepth: _goToDepth,
      );
    }
    final title = widget.title;
    if (title == null) return null;
    return Semantics(
      header: true,
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.titleLarge,
        child: title,
      ),
    );
  }

  Widget _buildEmptyState() {
    return widget.emptyState ??
        SymphonyEmptyState(
          title: widget.emptyTitle,
          message: widget.emptyMessage,
          icon: Icons.dashboard_outlined,
        );
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
        _openSubmenu(tileContext, item);
      case DashboardTapAction.select:
        onItemSelected?.call(item);
      case DashboardTapAction.navigate:
        navigateToDashboardItem(tileContext, item);
    }
  }

  void _openSubmenu(BuildContext tileContext, DashboardItem group) {
    switch (widget.submenuPresentation) {
      case DashboardSubmenuPresentation.inline:
        _controller.path = <String>[
          for (final opened in _openPath) opened.id,
          group.id,
        ];
      case DashboardSubmenuPresentation.page:
        _pushSubmenuPage(tileContext, <String>[group.id]);
    }
  }

  void _goToDepth(int depth) {
    _controller.path = <String>[
      for (final opened in _openPath.take(depth)) opened.id,
    ];
  }

  /// Drops the ids of [SymphonyDashboardController.path] that no longer
  /// resolve, once the current frame is done (listeners cannot be notified
  /// during a build).
  void _scheduleControllerSync() {
    if (_controllerSyncScheduled) return;
    _controllerSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllerSyncScheduled = false;
      if (!mounted) return;
      final controller = _controller;
      final resolved =
          DashboardMenu.resolveSubmenuPath(_visible, controller.path);
      if (resolved.length != controller.path.length) {
        controller.path = <String>[for (final group in resolved) group.id];
      }
    });
  }

  /// Publishes the new configuration to the open submenu pages once the
  /// current frame is done (they live in other routes and cannot be rebuilt
  /// during this build).
  void _schedulePageConfigSync() {
    if (_pageConfigSyncScheduled) return;
    _pageConfigSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageConfigSyncScheduled = false;
      if (mounted) _pageConfig.value = widget;
    });
  }

  void _pushSubmenuPage(BuildContext context, List<String> groupPath) {
    final navigator = Navigator.of(context);
    final Route<void> route;
    if (mounted) {
      final config = _pageConfig;
      route = MaterialPageRoute<void>(
        builder: (context) => ValueListenableBuilder<SymphonyDashboard>(
          valueListenable: config,
          builder: (context, dashboard, child) =>
              _buildSubmenuPage(dashboard, groupPath),
        ),
      );
    } else {
      // The dashboard is gone (a nested group was opened from a page that
      // outlived it): use its last configuration.
      final dashboard = _pageConfig.value;
      route = MaterialPageRoute<void>(
        builder: (context) => _buildSubmenuPage(dashboard, groupPath),
      );
    }
    unawaited(navigator.push<void>(route));
  }

  Widget _buildSubmenuPage(SymphonyDashboard config, List<String> groupPath) {
    return SymphonyDashboardSubmenuPage(
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
      onOpenSubmenu: _pushSubmenuPage,
      emptyState: config.emptyState,
      emptyTitle: config.emptyTitle,
      emptyMessage: config.emptyMessage,
    );
  }
}

/// Header of an inline submenu: a back button followed by the breadcrumb (or
/// the current group's label).
class _SubmenuHeader extends StatelessWidget {
  const _SubmenuHeader({
    required this.path,
    required this.rootLabel,
    required this.backLabel,
    required this.showBreadcrumbs,
    required this.onSelectDepth,
  });

  /// Opened groups, top level first. Never empty.
  final List<DashboardItem> path;
  final String rootLabel;
  final String backLabel;
  final bool showBreadcrumbs;

  /// Displays the level at the given depth (0 is the top level).
  final ValueChanged<int> onSelectDepth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = Semantics(
      header: true,
      child: Text(
        path.last.label,
        style: theme.textTheme.titleMedium,
        maxLines: showBreadcrumbs ? null : 1,
        overflow: showBreadcrumbs ? null : TextOverflow.ellipsis,
      ),
    );

    return Row(
      children: <Widget>[
        IconButton(
          tooltip: backLabel,
          icon: const BackButtonIcon(),
          onPressed: () => onSelectDepth(path.length - 1),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: !showBreadcrumbs
              ? current
              : Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    for (var depth = 0;
                        depth < path.length;
                        depth++) ...<Widget>[
                      TextButton(
                        onPressed: () => onSelectDepth(depth),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                          depth == 0 ? rootLabel : path[depth - 1].label,
                        ),
                      ),
                      ExcludeSemantics(
                        child: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    current,
                  ],
                ),
        ),
      ],
    );
  }
}
