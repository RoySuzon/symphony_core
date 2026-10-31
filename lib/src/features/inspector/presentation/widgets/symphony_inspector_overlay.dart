import 'package:flutter/material.dart';

import '../../data/api_inspector.dart';
import '../../domain/curl_command_builder.dart';
import '../api_inspector_strings.dart';
import '../screens/api_inspector_screen.dart';
import 'inspector_scope_binding.dart';

/// Wraps an application with a small, draggable floating button giving
/// access to the API inspector from anywhere.
///
/// The button shows the number of captured calls and a badge with the number
/// of failed calls. Tapping it opens [ApiInspectorScreen] as a full-screen
/// layer **inside** this widget, with its own nested [Navigator] (so it works
/// in `MaterialApp.builder`, where no navigator exists above the app) and a
/// close button returning to the app. While closed, only the button itself
/// receives pointer events: the rest of the app stays fully interactive.
///
/// ```dart
/// MaterialApp.router(
///   routerConfig: router,
///   builder: (context, child) => SymphonyInspectorOverlay(child: child!),
/// );
/// ```
///
/// * [inspector] defaults to `apiInspectorProvider` (requires a
///   `ProviderScope`); with an explicit inspector no `ProviderScope` is
///   needed.
/// * [enabled] defaults to `SymphonyConfig.enableInspector` when a
///   configuration is available, and to `true` otherwise. When disabled (or
///   when no inspector can be resolved) [child] is returned untouched.
///
/// On Android, the system back button closes the panel (or its inner pages)
/// in router based apps (`MaterialApp.router`); in `Navigator` based apps the
/// application navigator handles it first.
class SymphonyInspectorOverlay extends StatefulWidget {
  /// Wraps [child] with the inspector overlay.
  const SymphonyInspectorOverlay({
    super.key,
    required this.child,
    this.inspector,
    this.enabled,
    this.initialAlignment = Alignment.bottomRight,
    this.title = 'API Inspector',
    this.strings = const ApiInspectorStrings(),
    this.curlBuilder = const CurlCommandBuilder(),
    this.buttonSize = 52,
    this.margin = const EdgeInsets.all(12),
  });

  /// The application.
  final Widget child;

  /// Store to display. Defaults to `apiInspectorProvider`.
  final ApiInspector? inspector;

  /// Whether the floating button is shown. Defaults to
  /// `SymphonyConfig.enableInspector` (or `true` without configuration).
  final bool? enabled;

  /// Initial position of the button within the safe area (the user can drag
  /// it; it then snaps to the closest side).
  final Alignment initialAlignment;

  /// Title of the inspector screen.
  final String title;

  /// Texts of the inspector UI.
  final ApiInspectorStrings strings;

  /// Builder of the "copy as cURL" commands.
  final CurlCommandBuilder curlBuilder;

  /// Diameter of the floating button.
  final double buttonSize;

  /// Minimum distance between the button and the edges of the safe area.
  final EdgeInsets margin;

  /// Key of the floating button.
  static const Key buttonKey = ValueKey<String>(
    'symphony.inspector.overlay.button',
  );

  /// Key of the full-screen inspector panel.
  static const Key panelKey = ValueKey<String>(
    'symphony.inspector.overlay.panel',
  );

  @override
  State<SymphonyInspectorOverlay> createState() =>
      _SymphonyInspectorOverlayState();
}

class _SymphonyInspectorOverlayState extends State<SymphonyInspectorOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final InspectorScopeBinding _binding;
  late final AnimationController _panelController;
  late final Animation<double> _panelOpacity;
  late final Animation<Offset> _panelOffset;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late Alignment _alignment;
  bool _panelOpen = false;
  bool _closing = false;
  bool _dragging = false;

  ApiInspector? get _inspector => widget.inspector ?? _binding.inspector;

  bool get _active =>
      (widget.enabled ?? _binding.configEnabled ?? true) && _inspector != null;

  @override
  void initState() {
    super.initState();
    _binding = InspectorScopeBinding(onChanged: _onBindingChanged);
    _alignment = widget.initialAlignment;
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _panelOpacity = _panelController.drive(CurveTween(curve: Curves.easeOut));
    _panelOffset = _panelController.drive(
      Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    // Registered before the application's router (built below this widget),
    // so the back button reaches the open panel first.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind(listen: true);
  }

  @override
  void didUpdateWidget(covariant SymphonyInspectorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.inspector == null) != (widget.inspector == null) ||
        (oldWidget.enabled == null) != (widget.enabled == null)) {
      _bind(listen: false);
    }
    if (oldWidget.initialAlignment != widget.initialAlignment) {
      _alignment = widget.initialAlignment;
    }
    _closePanelIfInactive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _binding.dispose();
    _panelController.dispose();
    super.dispose();
  }

  void _bind({required bool listen}) {
    _binding.update(
      context,
      inspector: widget.inspector == null,
      config: widget.enabled == null,
      listen: listen,
    );
  }

  void _onBindingChanged() {
    rebuildInspectorState(this, () {
      setState(() {});
      _closePanelIfInactive();
    });
  }

  void _closePanelIfInactive() {
    if (_active || !_panelOpen) return;
    _panelController.value = 0;
    _panelOpen = false;
    _closing = false;
  }

  void _openPanel() {
    if (_panelOpen || !_active) return;
    setState(() {
      _panelOpen = true;
      _closing = false;
    });
    _panelController.forward();
  }

  void _closePanel() {
    if (!_panelOpen || _closing) return;
    _closing = true;
    _panelController.reverse().whenComplete(() {
      if (!mounted || !_closing) return;
      setState(() {
        _panelOpen = false;
        _closing = false;
      });
    });
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_panelOpen || _closing) return false;
    final navigator = _navigatorKey.currentState;
    if (navigator != null && await navigator.maybePop()) return true;
    _closePanel();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final inspector = _inspector;
    final active = _active && inspector != null;
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: <Widget>[
        ExcludeSemantics(
          excluding: active && _panelOpen && !_closing,
          child: widget.child,
        ),
        if (active && _panelOpen)
          Positioned.fill(child: _buildPanel())
        else if (active)
          Positioned.fill(child: _buildButtonLayer(inspector)),
      ],
    );
  }

  Widget _buildPanel() {
    return _InspectorHost(
      child: FadeTransition(
        opacity: _panelOpacity,
        child: SlideTransition(
          position: _panelOffset,
          child: KeyedSubtree(
            key: SymphonyInspectorOverlay.panelKey,
            // The panel's navigation notifications must not reach the
            // application (they drive Android's predictive back handling).
            child: NotificationListener<Notification>(
              onNotification: (_) => true,
              child: ScaffoldMessenger(
                child: HeroControllerScope.none(
                  child: Navigator(
                    key: _navigatorKey,
                    onGenerateRoute:
                        (settings) => MaterialPageRoute<void>(
                          settings: settings,
                          // Without an explicit inspector the screen follows
                          // apiInspectorProvider itself (even if it is rebuilt).
                          builder:
                              (_) => ApiInspectorScreen(
                                inspector: widget.inspector,
                                title: widget.title,
                                strings: widget.strings,
                                curlBuilder: widget.curlBuilder,
                                onClose: _closePanel,
                              ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonLayer(ApiInspector inspector) {
    return _InspectorHost(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = _buttonArea(context, constraints.biggest);
          final left = area.left + area.width * (_alignment.x + 1) / 2;
          final top = area.top + area.height * (_alignment.y + 1) / 2;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration:
                    _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: left,
                top: top,
                child: GestureDetector(
                  onPanStart: (_) => setState(() => _dragging = true),
                  onPanUpdate:
                      (details) => setState(
                        () =>
                            _alignment = _moved(
                              _alignment,
                              details.delta,
                              area,
                            ),
                      ),
                  onPanEnd:
                      (_) => setState(() {
                        _dragging = false;
                        _alignment = Alignment(
                          _alignment.x < 0 ? -1.0 : 1.0,
                          _alignment.y,
                        );
                      }),
                  onPanCancel: () => setState(() => _dragging = false),
                  child: _InspectorButton(
                    key: SymphonyInspectorOverlay.buttonKey,
                    inspector: inspector,
                    size: widget.buttonSize,
                    label: widget.strings.openInspectorLabel,
                    onTap: _openPanel,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The rectangle in which the top-left corner of the button may move.
  Rect _buttonArea(BuildContext context, Size size) {
    final padding = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    final insets = padding + widget.margin;
    final left = insets.left;
    final top = insets.top;
    final width = size.width - insets.horizontal - widget.buttonSize;
    final height = size.height - insets.vertical - widget.buttonSize;
    return Rect.fromLTWH(
      left,
      top,
      width < 0 ? 0 : width,
      height < 0 ? 0 : height,
    );
  }

  static Alignment _moved(Alignment alignment, Offset delta, Rect area) {
    final dx = area.width <= 0 ? 0.0 : delta.dx * 2 / area.width;
    final dy = area.height <= 0 ? 0.0 : delta.dy * 2 / area.height;
    return Alignment(
      (alignment.x + dx).clamp(-1.0, 1.0),
      (alignment.y + dy).clamp(-1.0, 1.0),
    );
  }
}

/// Provides the ambient widgets the inspector UI needs when the overlay is
/// placed above `MaterialApp` (or in a bare `WidgetsApp`).
class _InspectorHost extends StatelessWidget {
  const _InspectorHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var result = child;
    if (Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) ==
        null) {
      // Also provides a Directionality.
      result = Localizations(
        locale: const Locale('en', 'US'),
        delegates: const <LocalizationsDelegate<Object?>>[
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: result,
      );
    }
    if (MediaQuery.maybeSizeOf(context) == null) {
      final view = View.maybeOf(context);
      if (view != null) result = MediaQuery.fromView(view: view, child: result);
    }
    return result;
  }
}

class _InspectorButton extends StatelessWidget {
  const _InspectorButton({
    super.key,
    required this.inspector,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final ApiInspector inspector;
  final double size;
  final String label;
  final VoidCallback onTap;

  static String _count(int value) => value > 999 ? '999+' : '$value';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: inspector,
      builder: (context, _) {
        final total = inspector.calls.length;
        final errors = inspector.errorCount;
        final foreground = scheme.onInverseSurface;
        return Semantics(
          button: true,
          label: label,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: Material(
                    color: scheme.inverseSurface,
                    shape: const CircleBorder(),
                    elevation: 6,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onTap,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.http,
                            size: size * 0.42,
                            color: foreground,
                          ),
                          Text(
                            _count(total),
                            maxLines: 1,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (errors > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: IgnorePointer(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.surface, width: 1.5),
                        ),
                        child: Text(
                          _count(errors),
                          style: TextStyle(
                            color: scheme.onError,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
