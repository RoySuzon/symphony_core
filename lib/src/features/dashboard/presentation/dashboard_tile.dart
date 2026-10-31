import 'package:flutter/material.dart';

import '../domain/dashboard_item.dart';

/// Default tile of the dashboard grid.
///
/// A [Card] with an ink splash showing:
/// * the item's icon (or [DashboardItem.iconBuilder]) in a tinted circle, with
///   a [Badge] when [DashboardItem.badge] is set;
/// * the label (up to two lines) and, optionally, the description;
/// * a chevron in the top corner when the item opens a submenu;
/// * a greyed-out look when [DashboardItem.enabled] is `false`.
///
/// The content scales down instead of overflowing when the grid cell is
/// small (narrow screens, large text). The whole tile is exposed to
/// accessibility services as a single button.
///
/// Use it inside a custom `DashboardTileBuilder` to decorate the default
/// tile, or replace it entirely.
class SymphonyDashboardTile extends StatelessWidget {
  /// Creates a tile for [item].
  const SymphonyDashboardTile({
    super.key,
    required this.item,
    this.onTap,
    this.showDescription = true,
    this.iconSize = 28,
  }) : assert(iconSize > 0, 'iconSize must be positive.');

  /// The item displayed by the tile.
  final DashboardItem item;

  /// Called when the tile is tapped. Ignored when the item is disabled; the
  /// tile is not interactive when `null`.
  final VoidCallback? onTap;

  /// Whether [DashboardItem.description] is displayed under the label.
  final bool showDescription;

  /// Size of the icon. The tinted circle around it is proportionally larger.
  final double iconSize;

  // Material 3 emphasis levels expressed as alpha values (0-255).
  static const int _disabledContentAlpha = 97; // 38 %
  static const int _disabledContainerAlpha = 31; // 12 %
  static const int _accentContainerAlpha = 41; // 16 %

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = item.enabled;
    final accent = item.color;
    final disabledContent = scheme.onSurface.withAlpha(_disabledContentAlpha);

    final Color iconColor;
    final Color circleColor;
    if (!enabled) {
      iconColor = disabledContent;
      circleColor = scheme.onSurface.withAlpha(_disabledContainerAlpha);
    } else if (accent != null) {
      iconColor = accent;
      circleColor = accent.withAlpha(_accentContainerAlpha);
    } else {
      iconColor = scheme.onPrimaryContainer;
      circleColor = scheme.primaryContainer;
    }
    final labelColor = enabled ? scheme.onSurface : disabledContent;
    final secondaryColor = enabled ? scheme.onSurfaceVariant : disabledContent;

    final description = item.description;
    final hasDescription =
        showDescription && description != null && description.isNotEmpty;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildIcon(context, iconColor, circleColor),
        const SizedBox(height: 10),
        Text(
          item.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(color: labelColor),
        ),
        if (hasDescription) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
          ),
        ],
      ],
    );

    Widget body = Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
            return Center(child: content);
          }
          // Scale the content down rather than overflowing small cells.
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: constraints.maxWidth, child: content),
          );
        },
      ),
    );

    if (item.hasChildren) {
      body = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          body,
          PositionedDirectional(
            top: 6,
            end: 6,
            child: Icon(Icons.chevron_right, size: 18, color: secondaryColor),
          ),
        ],
      );
    }

    final badge = item.badge;
    // The card is the semantics container: the annotations below and the
    // ink well's tap action merge into a single button node.
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: enabled ? null : 0,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: item.label,
          value: badge == null || badge.isEmpty ? null : badge,
          hint: hasDescription ? description : null,
          child: ExcludeSemantics(child: body),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context, Color iconColor, Color circleColor) {
    final builder = item.iconBuilder;
    final data = item.icon;
    final Widget glyph;
    if (builder != null) {
      // Built below the tile's IconTheme so that `IconTheme.of(context)`
      // inside the builder returns the tile's icon color and size.
      glyph = Builder(builder: builder);
    } else if (data != null) {
      glyph = Icon(data);
    } else {
      final initial = item.label.trim().characters.take(1).toUpperCase();
      glyph =
          initial.isEmpty
              ? const Icon(Icons.apps)
              : Text(
                initial.toString(),
                style: TextStyle(
                  color: iconColor,
                  fontSize: iconSize * 0.8,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              );
    }

    Widget icon = DecoratedBox(
      decoration: ShapeDecoration(
        color: circleColor,
        shape: const CircleBorder(),
      ),
      child: Padding(
        padding: EdgeInsets.all(iconSize * 0.45),
        child: IconTheme.merge(
          data: IconThemeData(color: iconColor, size: iconSize),
          child: SizedBox.square(
            dimension: iconSize,
            child: Center(child: glyph),
          ),
        ),
      ),
    );

    final badge = item.badge;
    if (badge != null) {
      icon = Badge(label: badge.isEmpty ? null : Text(badge), child: icon);
    }
    return icon;
  }
}
