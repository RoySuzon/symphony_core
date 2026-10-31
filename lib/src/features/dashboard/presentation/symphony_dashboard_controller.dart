import 'package:flutter/foundation.dart';

/// Controls which submenu an inline `SymphonyDashboard` displays.
///
/// The [path] lists the ids of the opened groups, from the top level down to
/// the group whose children are displayed; it is empty at the top level. The
/// dashboard keeps it valid: ids that do not resolve to a visible, enabled
/// group (for example after the user lost a permission) are dropped right
/// after the next frame, so listeners always end up with the displayed level.
///
/// Use it to open submenus programmatically, to keep an app bar title in sync
/// or to let the platform back button close submenus with `PopScope`:
///
/// ```dart
/// final controller = SymphonyDashboardController();
///
/// ListenableBuilder(
///   listenable: controller,
///   builder: (context, child) => PopScope(
///     canPop: !controller.canGoBack,
///     onPopInvokedWithResult: (didPop, _) {
///       if (!didPop) controller.goBack();
///     },
///     child: child!,
///   ),
///   child: SymphonyDashboard(controller: controller),
/// );
/// ```
///
/// A controller drives a single dashboard at a time and is only used with
/// the inline submenu presentation. Dispose it when it is no longer needed.
class SymphonyDashboardController extends ChangeNotifier {
  /// Creates a controller, optionally starting inside the submenu described
  /// by [initialPath].
  SymphonyDashboardController({List<String> initialPath = const <String>[]})
    : _path = List<String>.unmodifiable(initialPath);

  List<String> _path;

  /// Ids of the opened groups, top level first. Empty at the top level.
  List<String> get path => _path;

  /// Replaces the opened submenu path and notifies listeners when it changed.
  set path(List<String> value) {
    if (listEquals(value, _path)) return;
    _path = List<String>.unmodifiable(value);
    notifyListeners();
  }

  /// Number of opened submenu levels; `0` at the top level.
  int get depth => _path.length;

  /// Whether the top level is displayed.
  bool get isAtRoot => _path.isEmpty;

  /// Whether a submenu is open, so that [goBack] has an effect.
  bool get canGoBack => _path.isNotEmpty;

  /// Id of the group whose children are displayed, or `null` at the top
  /// level.
  String? get currentGroupId => _path.isEmpty ? null : _path.last;

  /// Opens the group [groupId], which must be a child of the current level.
  void open(String groupId) => path = <String>[..._path, groupId];

  /// Closes the current submenu. Returns `false` (and does nothing) at the
  /// top level.
  bool goBack() {
    if (_path.isEmpty) return false;
    path = _path.sublist(0, _path.length - 1);
    return true;
  }

  /// Displays the level at [depth]: `0` is the top level, `1` the children of
  /// the first opened group, and so on.
  ///
  /// Throws a [RangeError] unless `0 <= depth <= this.depth`.
  void goToDepth(int depth) {
    RangeError.checkValueInInterval(depth, 0, _path.length, 'depth');
    path = _path.sublist(0, depth);
  }

  /// Returns to the top level.
  void goToRoot() => path = const <String>[];
}
