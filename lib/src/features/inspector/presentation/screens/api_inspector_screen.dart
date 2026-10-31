import 'package:flutter/material.dart';

import '../../../../ui/widgets/feedback/symphony_empty_state.dart';
import '../../../../ui/widgets/feedback/symphony_error_view.dart';
import '../../data/api_inspector.dart';
import '../../domain/api_call_filter.dart';
import '../../domain/api_call_record.dart';
import '../../domain/curl_command_builder.dart';
import '../api_inspector_strings.dart';
import '../widgets/api_call_tile.dart';
import '../widgets/inspector_scope_binding.dart';
import 'api_call_detail_screen.dart';

/// Pushes an [ApiInspectorScreen] on the nearest [Navigator] of [context]
/// (or the root navigator when [rootNavigator] is true).
///
/// Without an explicit [inspector] the screen shows the shared inspector of
/// `apiInspectorProvider` visible from [context].
///
/// ```dart
/// IconButton(
///   icon: const Icon(Icons.http),
///   onPressed: () => showApiInspector(context),
/// );
/// ```
Future<void> showApiInspector(
  BuildContext context, {
  ApiInspector? inspector,
  String title = 'API Inspector',
  ApiInspectorStrings strings = const ApiInspectorStrings(),
  CurlCommandBuilder curlBuilder = const CurlCommandBuilder(),
  bool rootNavigator = false,
}) {
  final resolved = inspector ?? InspectorScopeBinding.read(context);
  return Navigator.of(context, rootNavigator: rootNavigator).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ApiInspectorScreen(
        inspector: resolved,
        title: title,
        strings: strings,
        curlBuilder: curlBuilder,
      ),
    ),
  );
}

/// The API inspector: a searchable, filterable list of captured HTTP calls.
///
/// Shows [inspector], or the shared inspector of `apiInspectorProvider` when
/// [inspector] is null (an explanatory message is shown when neither is
/// available). The app bar holds a pause/resume recording toggle and a
/// clear-all action (with confirmation); below it, a search field and status
/// filter chips with per-category counts narrow the list (newest first).
/// Tapping a call opens its [ApiCallDetailScreen].
///
/// Push it with [showApiInspector], add it to your routes, or let
/// `SymphonyInspectorOverlay` open it from a floating button.
class ApiInspectorScreen extends StatefulWidget {
  /// Creates the inspector screen.
  const ApiInspectorScreen({
    super.key,
    this.inspector,
    this.title = 'API Inspector',
    this.strings = const ApiInspectorStrings(),
    this.curlBuilder = const CurlCommandBuilder(),
    this.onClose,
  });

  /// Store to display. Defaults to `apiInspectorProvider`.
  final ApiInspector? inspector;

  /// App bar title.
  final String title;

  /// Texts.
  final ApiInspectorStrings strings;

  /// Builder of the "copy as cURL" commands of the detail screen.
  final CurlCommandBuilder curlBuilder;

  /// When provided, a close button calling it is shown as the leading app
  /// bar action (used by `SymphonyInspectorOverlay`).
  final VoidCallback? onClose;

  /// Key of the search field.
  static const Key searchFieldKey =
      ValueKey<String>('symphony.inspector.search');

  /// Key of the clear-all button.
  static const Key clearAllButtonKey =
      ValueKey<String>('symphony.inspector.clearAll');

  /// Key of the pause/resume recording button.
  static const Key recordingButtonKey =
      ValueKey<String>('symphony.inspector.recording');

  /// Key of the close button (present when [onClose] is set).
  static const Key closeButtonKey =
      ValueKey<String>('symphony.inspector.close');

  /// Key of the chip filtering on [status].
  static Key filterChipKey(ApiCallStatusFilter status) =>
      ValueKey<String>('symphony.inspector.filter.${status.name}');

  @override
  State<ApiInspectorScreen> createState() => _ApiInspectorScreenState();
}

class _ApiInspectorScreenState extends State<ApiInspectorScreen> {
  late final InspectorScopeBinding _binding =
      InspectorScopeBinding(onChanged: _onBindingChanged);
  final TextEditingController _searchController = TextEditingController();
  ApiCallFilter _filter = ApiCallFilter.none;

  ApiInspector? get _inspector => widget.inspector ?? _binding.inspector;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _binding.update(context, inspector: widget.inspector == null);
  }

  @override
  void didUpdateWidget(covariant ApiInspectorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.inspector == null) != (widget.inspector == null)) {
      _binding.update(
        context,
        inspector: widget.inspector == null,
        listen: false,
      );
    }
  }

  @override
  void dispose() {
    _binding.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onBindingChanged() =>
      rebuildInspectorState(this, () => setState(() {}));

  void _setQuery(String query) {
    setState(() => _filter = _filter.copyWith(query: query));
  }

  void _setStatus(ApiCallStatusFilter status) {
    setState(() => _filter = _filter.copyWith(status: status));
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _filter = ApiCallFilter.none);
  }

  Future<void> _confirmClear(ApiInspector inspector) async {
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.clearAllTitle),
        content: Text(strings.clearAllMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.clearAllConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) inspector.clear();
  }

  void _openDetails(ApiInspector inspector, ApiCallRecord record) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiCallDetailScreen(
          record: record,
          inspector: inspector,
          strings: widget.strings,
          curlBuilder: widget.curlBuilder,
        ),
      ),
    );
  }

  Widget? _closeButton() {
    final onClose = widget.onClose;
    if (onClose == null) return null;
    return IconButton(
      key: ApiInspectorScreen.closeButtonKey,
      icon: const Icon(Icons.close),
      tooltip: widget.strings.closeTooltip,
      onPressed: onClose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inspector = _inspector;
    if (inspector == null) {
      return Scaffold(
        appBar: AppBar(leading: _closeButton(), title: Text(widget.title)),
        body: SymphonyErrorView(
          icon: Icons.manage_search,
          title: widget.strings.unavailableTitle,
          message: widget.strings.unavailableMessage,
        ),
      );
    }
    return ListenableBuilder(
      listenable: inspector,
      builder: (context, _) => _buildInspector(context, inspector),
    );
  }

  Widget _buildInspector(BuildContext context, ApiInspector inspector) {
    final strings = widget.strings;
    final calls = inspector.calls;
    final queried = calls.where(_filter.matchesQuery).toList(growable: false);
    final counts = ApiCallFilter.countByStatus(queried);
    final visible = queried.where(_filter.status.matches).toList();
    return Scaffold(
      appBar: AppBar(
        leading: _closeButton(),
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            key: ApiInspectorScreen.recordingButtonKey,
            icon: Icon(
              inspector.enabled
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
            tooltip: inspector.enabled
                ? strings.pauseRecordingTooltip
                : strings.resumeRecordingTooltip,
            onPressed: () => inspector.enabled = !inspector.enabled,
          ),
          IconButton(
            key: ApiInspectorScreen.clearAllButtonKey,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: strings.clearAllTooltip,
            onPressed: calls.isEmpty ? null : () => _confirmClear(inspector),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Sized by its content (not a fixed-height AppBar.bottom) so that
          // large text scales never overflow.
          _SearchField(
            controller: _searchController,
            strings: strings,
            onChanged: _setQuery,
          ),
          _StatusChips(
            selected: _filter.status,
            counts: counts,
            strings: strings,
            onSelected: _setStatus,
          ),
          const Divider(height: 1),
          if (!inspector.enabled)
            _PausedBanner(
              strings: strings,
              onResume: () => inspector.enabled = true,
            ),
          Expanded(
            child: _buildList(context, inspector, calls, visible),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    ApiInspector inspector,
    List<ApiCallRecord> calls,
    List<ApiCallRecord> visible,
  ) {
    final strings = widget.strings;
    if (calls.isEmpty) {
      return SymphonyEmptyState(
        icon: Icons.travel_explore,
        title: strings.emptyTitle,
        message: strings.emptyMessage,
      );
    }
    if (visible.isEmpty) {
      return SymphonyEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: strings.noMatchesTitle,
        message: strings.noMatchesMessage,
        actionLabel: strings.clearFilters,
        onAction: _clearFilters,
      );
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = visible[index];
        return ApiCallTile(
          key: ValueKey<int>(record.id),
          record: record,
          strings: strings,
          onTap: () => _openDetails(inspector, record),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.strings,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ApiInspectorStrings strings;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          key: ApiInspectorScreen.searchFieldKey,
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: strings.searchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: strings.clearSearchTooltip,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.selected,
    required this.counts,
    required this.strings,
    required this.onSelected,
  });

  final ApiCallStatusFilter selected;
  final Map<ApiCallStatusFilter, int> counts;
  final ApiInspectorStrings strings;
  final ValueChanged<ApiCallStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: <Widget>[
          for (final status in ApiCallStatusFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                key: ApiInspectorScreen.filterChipKey(status),
                label: Text(
                  '${strings.filterLabel(status)} ${counts[status] ?? 0}',
                ),
                selected: selected == status,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelected(status),
              ),
            ),
        ],
      ),
    );
  }
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner({required this.strings, required this.onResume});

  final ApiInspectorStrings strings;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: <Widget>[
            Icon(Icons.pause, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.recordingPaused,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
                onPressed: onResume, child: Text(strings.resumeRecording)),
          ],
        ),
      ),
    );
  }
}
