import 'package:flutter/material.dart';

import '../domain/dashboard_item.dart';
import 'dashboard_tile.dart';

/// Builds a custom tile for [item].
///
/// [onTap] runs the dashboard's tap handling (open the submenu, navigate,
/// notify `onItemSelected`...). It is `null` when the item is disabled or
/// when the grid has no tap handler. Wrap [SymphonyDashboardTile] to
/// decorate the default tile.
typedef DashboardTileBuilder =
    Widget Function(
      BuildContext context,
      DashboardItem item,
      VoidCallback? onTap,
    );

/// Handles a tap on the tile of [item]; [context] is the tile's context.
typedef DashboardItemTapHandler =
    void Function(BuildContext context, DashboardItem item);

/// A scrollable grid of dashboard tiles.
///
/// It displays exactly [items], in order: it neither filters them by access
/// nor manages submenus. Use `SymphonyDashboard` for that; this widget is the
/// building block it uses, also handy for custom screens.
///
/// By default columns adapt to the available width ([maxCrossAxisExtent]);
/// set [crossAxisCount] for a fixed number of columns.
class SymphonyDashboardGrid extends StatelessWidget {
  /// Creates a grid of tiles for [items].
  const SymphonyDashboardGrid({
    super.key,
    required this.items,
    this.onItemTap,
    this.tileBuilder,
    this.header,
    this.emptyState,
    this.maxCrossAxisExtent = 180,
    this.crossAxisCount,
    this.childAspectRatio = 1,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(16),
    this.shrinkWrap = false,
    this.physics,
  }) : assert(maxCrossAxisExtent > 0, 'maxCrossAxisExtent must be positive.'),
       assert(
         crossAxisCount == null || crossAxisCount > 0,
         'crossAxisCount must be positive.',
       ),
       assert(childAspectRatio > 0, 'childAspectRatio must be positive.'),
       assert(spacing >= 0, 'spacing must not be negative.');

  /// The items to display.
  final List<DashboardItem> items;

  /// Called when an enabled tile is tapped. Tiles are not interactive when
  /// `null`.
  final DashboardItemTapHandler? onItemTap;

  /// Builds custom tiles. Defaults to [SymphonyDashboardTile].
  final DashboardTileBuilder? tileBuilder;

  /// Widget scrolled above the tiles (a title, a breadcrumb...).
  final Widget? header;

  /// Widget displayed instead of the tiles when [items] is empty. Nothing is
  /// displayed when `null`.
  final Widget? emptyState;

  /// Maximum width of a tile when [crossAxisCount] is `null`: the grid uses
  /// as many columns as needed to keep tiles at most this wide.
  final double maxCrossAxisExtent;

  /// Fixed number of columns. Overrides [maxCrossAxisExtent].
  final int? crossAxisCount;

  /// Width / height ratio of the tiles.
  final double childAspectRatio;

  /// Horizontal and vertical gap between tiles, also used between [header]
  /// and the tiles.
  final double spacing;

  /// Padding around the content.
  final EdgeInsetsGeometry padding;

  /// Whether the grid sizes itself to its content (for example inside
  /// another scroll view) instead of filling the available height.
  final bool shrinkWrap;

  /// Scroll physics of the grid.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding = padding.resolve(Directionality.of(context));
    final header = this.header;
    final slivers = <Widget>[];
    if (header != null) {
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            resolvedPadding.left,
            resolvedPadding.top,
            resolvedPadding.right,
            spacing,
          ),
          sliver: SliverToBoxAdapter(child: header),
        ),
      );
    }
    final bodyPadding = EdgeInsets.fromLTRB(
      resolvedPadding.left,
      header == null ? resolvedPadding.top : 0,
      resolvedPadding.right,
      resolvedPadding.bottom,
    );

    if (items.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: bodyPadding,
          sliver: SliverGrid(
            gridDelegate: _gridDelegate(),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildTile(items[index]),
              childCount: items.length,
              findChildIndexCallback: _findChildIndex,
            ),
          ),
        ),
      );
    } else {
      final emptyState = this.emptyState;
      if (emptyState != null) {
        slivers.add(
          shrinkWrap
              ? SliverPadding(
                padding: bodyPadding,
                sliver: SliverToBoxAdapter(child: emptyState),
              )
              : SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(padding: bodyPadding, child: emptyState),
              ),
        );
      }
    }

    return CustomScrollView(
      shrinkWrap: shrinkWrap,
      physics: physics,
      slivers: slivers,
    );
  }

  SliverGridDelegate _gridDelegate() {
    final count = crossAxisCount;
    if (count != null) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      );
    }
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCrossAxisExtent,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
    );
  }

  int? _findChildIndex(Key key) {
    if (key is! ValueKey<String>) return null;
    final index = items.indexWhere((item) => item.id == key.value);
    return index < 0 ? null : index;
  }

  Widget _buildTile(DashboardItem item) {
    return Builder(
      key: ValueKey<String>(item.id),
      builder: (tileContext) {
        final handler = onItemTap;
        final VoidCallback? onTap =
            item.enabled && handler != null
                ? () => handler(tileContext, item)
                : null;
        final builder = tileBuilder;
        if (builder != null) return builder(tileContext, item, onTap);
        return SymphonyDashboardTile(item: item, onTap: onTap);
      },
    );
  }
}
