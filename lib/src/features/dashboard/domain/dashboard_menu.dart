import 'package:flutter/foundation.dart';

import '../../../core/access/access_context.dart';
import 'dashboard_item.dart';

/// What tapping a [DashboardItem] does, as resolved by
/// [DashboardMenu.resolveTapAction].
enum DashboardTapAction {
  /// Nothing happens: the item is disabled, or it is a leaf without
  /// destination and no selection handler is installed.
  none,

  /// [DashboardItem.onTap] is called.
  custom,

  /// The submenu made of [DashboardItem.children] is opened.
  openSubmenu,

  /// The item is reported to the dashboard's `onItemSelected` handler, which
  /// replaces the built-in navigation.
  select,

  /// The dashboard navigates to [DashboardItem.routeName] or
  /// [DashboardItem.route].
  navigate,
}

/// Pure, framework independent operations on a dashboard menu tree.
///
/// Every method treats the given list as the top level of the menu and walks
/// [DashboardItem.children] recursively. None of them mutates its input.
abstract final class DashboardMenu {
  /// Returns the items of [items] that [context] may see.
  ///
  /// Rules, applied recursively:
  /// * an item whose [DashboardItem.access] is not satisfied is hidden
  ///   together with all of its children;
  /// * a group whose children are all hidden is hidden as well, unless it has
  ///   its own action ([DashboardItem.hasAction]); it is then kept as a leaf;
  /// * disabled items ([DashboardItem.enabled] `false`) stay visible.
  ///
  /// Groups whose children changed are copied with the visible children only;
  /// unchanged items are returned as is.
  static List<DashboardItem> filterVisibleItems(
    List<DashboardItem> items,
    AccessContext context,
  ) {
    final visible = <DashboardItem>[];
    for (final item in items) {
      final filtered = _filterItem(item, context);
      if (filtered != null) visible.add(filtered);
    }
    return List<DashboardItem>.unmodifiable(visible);
  }

  static DashboardItem? _filterItem(DashboardItem item, AccessContext context) {
    if (!item.access.isSatisfiedBy(context)) return null;
    if (item.isLeaf) return item;
    final children = <DashboardItem>[];
    var changed = false;
    for (final child in item.children) {
      final filtered = _filterItem(child, context);
      if (filtered == null) {
        changed = true;
      } else {
        if (!identical(filtered, child)) changed = true;
        children.add(filtered);
      }
    }
    if (children.isEmpty && !item.hasAction) return null;
    if (!changed) return item;
    return item.copyWith(children: List<DashboardItem>.unmodifiable(children));
  }

  /// Finds the item with [id] anywhere in the tree (depth-first), or returns
  /// `null`.
  static DashboardItem? findItemById(List<DashboardItem> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
      final nested = findItemById(item.children, id);
      if (nested != null) return nested;
    }
    return null;
  }

  /// Returns the chain of items leading to the item with [id], from the top
  /// level down to the item itself (inclusive). Useful for breadcrumbs.
  ///
  /// Returns an empty list when no item has [id].
  static List<DashboardItem> pathTo(List<DashboardItem> items, String id) {
    final path = <DashboardItem>[];
    return _collectPath(items, id, path)
        ? List<DashboardItem>.unmodifiable(path)
        : const <DashboardItem>[];
  }

  static bool _collectPath(
    List<DashboardItem> items,
    String id,
    List<DashboardItem> path,
  ) {
    for (final item in items) {
      path.add(item);
      if (item.id == id || _collectPath(item.children, id, path)) return true;
      path.removeLast();
    }
    return false;
  }

  /// Returns every item of the tree in depth-first pre-order: each group is
  /// followed by its descendants.
  static List<DashboardItem> flatten(List<DashboardItem> items) {
    final all = <DashboardItem>[];
    void visit(List<DashboardItem> level) {
      for (final item in level) {
        all.add(item);
        visit(item.children);
      }
    }

    visit(items);
    return List<DashboardItem>.unmodifiable(all);
  }

  /// Resolves a submenu [path] (ids of nested groups, top level first)
  /// against [items].
  ///
  /// Returns the longest valid prefix as items: each entry must be an
  /// enabled group ([DashboardItem.hasChildren]) found among the children of
  /// the previous entry (or among [items] for the first one). Resolution
  /// stops at the first id that does not match, so the result is the nearest
  /// level that still exists, for example after the user lost a permission.
  static List<DashboardItem> resolveSubmenuPath(
    List<DashboardItem> items,
    List<String> path,
  ) {
    final resolved = <DashboardItem>[];
    var level = items;
    for (final id in path) {
      DashboardItem? match;
      for (final item in level) {
        if (item.id == id) {
          match = item;
          break;
        }
      }
      if (match == null || !match.enabled || !match.hasChildren) break;
      resolved.add(match);
      level = match.children;
    }
    return List<DashboardItem>.unmodifiable(resolved);
  }

  /// Returns the ids used by more than one item of the tree.
  static Set<String> duplicateIds(List<DashboardItem> items) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final item in flatten(items)) {
      if (!seen.add(item.id)) duplicates.add(item.id);
    }
    return duplicates;
  }

  /// Verifies in debug builds that every id of the tree is unique.
  ///
  /// Throws a [FlutterError] listing the duplicated ids. Always returns
  /// `true` so it can be used inside an `assert`:
  ///
  /// ```dart
  /// assert(DashboardMenu.debugAssertUniqueIds(items));
  /// ```
  static bool debugAssertUniqueIds(List<DashboardItem> items) {
    assert(() {
      final duplicates = duplicateIds(items);
      if (duplicates.isNotEmpty) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'Duplicate DashboardItem ids: ${duplicates.join(', ')}.',
          ),
          ErrorDescription(
            'Every DashboardItem id must be unique across the whole menu '
            'tree, nested children included, because submenus, breadcrumbs '
            'and lookups are resolved by id.',
          ),
          ErrorHint(
            'Give each item a distinct id, for example by prefixing the ids '
            'of children with the id of their group ("sales.orders").',
          ),
        ]);
      }
      return true;
    }());
    return true;
  }

  /// Resolves what tapping [item] does, in order of precedence:
  ///
  /// 1. disabled items do nothing ([DashboardTapAction.none]);
  /// 2. [DashboardItem.onTap] wins over everything else
  ///    ([DashboardTapAction.custom]);
  /// 3. groups open their submenu ([DashboardTapAction.openSubmenu]);
  /// 4. leaves are reported to the selection handler when
  ///    [hasSelectionHandler] is `true` ([DashboardTapAction.select]);
  /// 5. leaves with a destination navigate ([DashboardTapAction.navigate]);
  /// 6. anything else does nothing.
  static DashboardTapAction resolveTapAction(
    DashboardItem item, {
    bool hasSelectionHandler = false,
  }) {
    if (!item.enabled) return DashboardTapAction.none;
    if (item.onTap != null) return DashboardTapAction.custom;
    if (item.hasChildren) return DashboardTapAction.openSubmenu;
    if (hasSelectionHandler) return DashboardTapAction.select;
    if (item.hasDestination) return DashboardTapAction.navigate;
    return DashboardTapAction.none;
  }
}
