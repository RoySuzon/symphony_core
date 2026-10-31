import 'package:flutter/widgets.dart';

import '../../../core/access/access_requirement.dart';

/// How a dashboard navigates to the destination of a [DashboardItem] when the
/// application uses GoRouter.
enum DashboardNavigation {
  /// Declarative navigation with `GoRouter.go` / `GoRouter.goNamed`. This is
  /// the default.
  ///
  /// The destination replaces the current location, so the browser URL and
  /// deep links always match what is displayed. Declare module routes as
  /// sub-routes of the dashboard route (for example `/home/orders`) to keep a
  /// back button to the dashboard, or use [push].
  go,

  /// Imperative navigation with `GoRouter.push` / `GoRouter.pushNamed`.
  ///
  /// The destination is stacked on top of the dashboard, so popping it always
  /// returns to the dashboard, whatever the route hierarchy is.
  push,
}

/// Builds a custom icon (asset image, SVG, avatar...) for a [DashboardItem].
///
/// The default tile calls it below an [IconTheme] whose color and size match
/// the tile and renders the result inside its tinted circle: [Icon] widgets
/// pick the theme up automatically and `IconTheme.of(context)` returns it
/// (useful to tint an SVG).
typedef DashboardIconBuilder = Widget Function(BuildContext context);

/// Custom action executed when a [DashboardItem] is tapped.
///
/// [context] is the build context of the tapped tile.
typedef DashboardItemTapCallback = void Function(BuildContext context);

/// An entry of the dashboard module menu.
///
/// Items are immutable values supplied by the application: the package never
/// assumes which modules, routes or permissions exist. An item is either
///
/// * a **leaf** that navigates to [routeName] or [route], or runs [onTap]; or
/// * a **group** whose [children] form a nested submenu of any depth.
///
/// Visibility restrictions are opt-in: by default an item is visible to
/// everybody ([AccessRequirement.none]). Set [access] to restrict it to
/// signed-in users, roles, permissions or a custom predicate. A group whose
/// children are all hidden is hidden as well, unless it has its own
/// destination or [onTap].
///
/// ```dart
/// const DashboardItem(
///   id: 'sales',
///   label: 'Sales',
///   icon: Icons.point_of_sale,
///   access: AccessRequirement(roles: {'sales', 'admin'}),
///   children: [
///     DashboardItem(
///       id: 'sales.orders',
///       label: 'Orders',
///       icon: Icons.receipt_long,
///       routeName: 'orders',
///       badge: '3',
///     ),
///     DashboardItem(
///       id: 'sales.invoice',
///       label: 'Invoice',
///       routeName: 'invoice',
///       pathParameters: {'invoiceId': '42'},
///       navigation: DashboardNavigation.push,
///       access: AccessRequirement(permissions: {'invoices.read'}),
///     ),
///   ],
/// );
/// ```
///
/// Two items are equal when their [id]s are equal. Ids must therefore be
/// unique across the whole menu tree, nested children included.
@immutable
class DashboardItem {
  /// Creates a dashboard item.
  const DashboardItem({
    required this.id,
    required this.label,
    this.icon,
    this.iconBuilder,
    this.description,
    this.route,
    this.routeName,
    this.pathParameters = const <String, String>{},
    this.queryParameters = const <String, dynamic>{},
    this.extra,
    this.navigation = DashboardNavigation.go,
    this.children = const <DashboardItem>[],
    this.access = AccessRequirement.none,
    this.badge,
    this.color,
    this.enabled = true,
    this.onTap,
    this.metadata = const <String, Object?>{},
  }) : assert(id != '', 'DashboardItem.id must not be empty.');

  /// Stable identifier, unique across the whole menu tree.
  ///
  /// Used for equality, submenu paths, breadcrumbs and lookups.
  final String id;

  /// Text displayed on the tile (up to two lines) and in breadcrumbs.
  final String label;

  /// Icon displayed on the tile. Ignored when [iconBuilder] is set.
  ///
  /// When neither is set, the tile shows the first letter of [label].
  final IconData? icon;

  /// Builds a custom icon such as an asset image or an SVG. Takes precedence
  /// over [icon].
  final DashboardIconBuilder? iconBuilder;

  /// Optional secondary text displayed under the label.
  final String? description;

  /// Destination location, for example `/orders` or `/orders?status=open`.
  ///
  /// Navigated to with GoRouter according to [navigation]. Without GoRouter
  /// it is used as a `Navigator` named route. Entries of [queryParameters]
  /// are merged into its query string (see [routeLocation]).
  final String? route;

  /// Name of the destination `GoRoute`. Takes precedence over [route].
  ///
  /// The location is built by GoRouter from [pathParameters] and
  /// [queryParameters].
  final String? routeName;

  /// Path parameters used with [routeName], for example `{'id': '42'}` for a
  /// route declared as `/orders/:id`.
  final Map<String, String> pathParameters;

  /// Query parameters appended to the destination (with [routeName] or
  /// [route]).
  ///
  /// Values should be strings or iterables of strings; other values are
  /// converted with `toString()` and `null` values are dropped (see
  /// [routeQueryParameters]).
  final Map<String, dynamic> queryParameters;

  /// Extra object passed to the destination (`GoRouterState.extra`, or the
  /// route arguments when navigating with `Navigator`).
  final Object? extra;

  /// Whether the destination replaces the current location
  /// ([DashboardNavigation.go], the default) or is pushed on top of it
  /// ([DashboardNavigation.push]).
  final DashboardNavigation navigation;

  /// Nested submenu entries. A non-empty list makes this item a group:
  /// tapping it opens the submenu instead of navigating.
  final List<DashboardItem> children;

  /// Who may see the item. Defaults to [AccessRequirement.none] (everybody).
  ///
  /// The requirement of a group also applies to all of its [children].
  final AccessRequirement access;

  /// Short text displayed in a badge on the icon, for example a counter.
  ///
  /// An empty string displays a small dot without text. `null` hides the
  /// badge.
  final String? badge;

  /// Accent color of the tile's icon. The icon circle uses a translucent
  /// tint of it. Defaults to the theme's primary container colors.
  final Color? color;

  /// Whether the item can be tapped. Disabled items stay visible but are
  /// rendered greyed out and ignore taps.
  final bool enabled;

  /// Custom action executed on tap instead of the default behaviour (opening
  /// the submenu or navigating).
  final DashboardItemTapCallback? onTap;

  /// Free-form data for application specific needs, for example analytics
  /// identifiers or values read by a custom tile builder.
  final Map<String, Object?> metadata;

  /// Whether the item has nested [children] (it is a group).
  bool get hasChildren => children.isNotEmpty;

  /// Whether the item has no [children].
  bool get isLeaf => children.isEmpty;

  /// Whether the item declares a navigation destination ([routeName] or
  /// [route]).
  bool get hasDestination =>
      (routeName?.isNotEmpty ?? false) || (route?.isNotEmpty ?? false);

  /// Whether tapping the item does something on its own, without its
  /// [children]: it has a destination or an [onTap] callback.
  bool get hasAction => hasDestination || onTap != null;

  /// [queryParameters] normalized for URIs: strings and iterables of strings
  /// are kept, other values are converted with `toString()` and `null`
  /// values are dropped.
  Map<String, dynamic> get routeQueryParameters {
    if (queryParameters.isEmpty) return const <String, dynamic>{};
    final normalized = <String, dynamic>{};
    queryParameters.forEach((key, value) {
      if (value == null) return;
      if (value is String) {
        normalized[key] = value;
      } else if (value is Iterable<Object?>) {
        normalized[key] = <String>[
          for (final element in value)
            if (element != null) element.toString(),
        ];
      } else {
        normalized[key] = value.toString();
      }
    });
    return normalized;
  }

  /// The location used to navigate to [route]: [route] with
  /// [queryParameters] merged into its query string (the item's values win
  /// on conflicts). `null` when [route] is not set.
  String? get routeLocation {
    final location = route;
    if (location == null || location.isEmpty) return null;
    final query = routeQueryParameters;
    if (query.isEmpty) return location;
    final uri = Uri.parse(location);
    return uri.replace(
      queryParameters: <String, dynamic>{
        ...uri.queryParametersAll,
        ...query,
      },
    ).toString();
  }

  /// Returns a copy with the given fields replaced. `null` arguments keep the
  /// current values.
  DashboardItem copyWith({
    String? id,
    String? label,
    IconData? icon,
    DashboardIconBuilder? iconBuilder,
    String? description,
    String? route,
    String? routeName,
    Map<String, String>? pathParameters,
    Map<String, dynamic>? queryParameters,
    Object? extra,
    DashboardNavigation? navigation,
    List<DashboardItem>? children,
    AccessRequirement? access,
    String? badge,
    Color? color,
    bool? enabled,
    DashboardItemTapCallback? onTap,
    Map<String, Object?>? metadata,
  }) {
    return DashboardItem(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      iconBuilder: iconBuilder ?? this.iconBuilder,
      description: description ?? this.description,
      route: route ?? this.route,
      routeName: routeName ?? this.routeName,
      pathParameters: pathParameters ?? this.pathParameters,
      queryParameters: queryParameters ?? this.queryParameters,
      extra: extra ?? this.extra,
      navigation: navigation ?? this.navigation,
      children: children ?? this.children,
      access: access ?? this.access,
      badge: badge ?? this.badge,
      color: color ?? this.color,
      enabled: enabled ?? this.enabled,
      onTap: onTap ?? this.onTap,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) => other is DashboardItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    final kind = hasChildren ? ', children: ${children.length}' : '';
    final target = routeName ?? route;
    final destination = target == null ? '' : ', destination: $target';
    return 'DashboardItem($id, label: $label$kind$destination'
        '${enabled ? '' : ', disabled'})';
  }
}
