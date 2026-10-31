import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api_inspector.dart';
import '../../domain/api_call_record.dart';
import '../../domain/curl_command_builder.dart';
import '../api_inspector_strings.dart';
import '../widgets/api_call_tile.dart';

/// Details of one captured call, in three tabs: **Overview** (URL, status,
/// timing, errors), **Request** (query parameters, headers, body, cURL) and
/// **Response** (headers, body).
///
/// Every value is selectable and can be copied; the app bar copies the call
/// as a cURL command (built from redacted data). When [inspector] is given
/// the screen follows the call live, e.g. while it is still pending.
class ApiCallDetailScreen extends StatelessWidget {
  /// Creates the detail screen of [record].
  const ApiCallDetailScreen({
    super.key,
    required this.record,
    this.inspector,
    this.strings = const ApiInspectorStrings(),
    this.curlBuilder = const CurlCommandBuilder(),
  });

  /// The call to display (its latest version is read from [inspector] when
  /// available).
  final ApiCallRecord record;

  /// Inspector used to follow updates of [record].
  final ApiInspector? inspector;

  /// Texts.
  final ApiInspectorStrings strings;

  /// Builder of the "copy as cURL" command.
  final CurlCommandBuilder curlBuilder;

  /// Key of the app bar button copying the call as cURL.
  static const Key copyCurlButtonKey =
      ValueKey<String>('symphony.inspector.detail.copyCurl');

  @override
  Widget build(BuildContext context) {
    final source = inspector;
    if (source == null) return _buildContent(context, record);
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) =>
          _buildContent(context, source.byId(record.id) ?? record),
    );
  }

  Widget _buildContent(BuildContext context, ApiCallRecord call) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: <Widget>[
              ApiCallMethodBadge(method: call.method),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  call.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              key: copyCurlButtonKey,
              icon: const Icon(Icons.terminal),
              tooltip: strings.copyCurlTooltip,
              onPressed: () =>
                  _copyText(context, curlBuilder.build(call), strings),
            ),
          ],
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: strings.overviewTab),
              Tab(text: strings.requestTab),
              Tab(text: strings.responseTab),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _OverviewTab(call: call, strings: strings),
            _RequestTab(call: call, strings: strings, curlBuilder: curlBuilder),
            _ResponseTab(call: call, strings: strings),
          ],
        ),
      ),
    );
  }
}

Future<void> _copyText(
  BuildContext context,
  String text,
  ApiInspectorStrings strings,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(strings.copiedMessage),
        duration: const Duration(seconds: 2),
      ),
    );
}

String _headersText(Map<String, String> headers) =>
    headers.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.call, required this.strings});

  final ApiCallRecord call;
  final ApiInspectorStrings strings;

  @override
  Widget build(BuildContext context) {
    final code = call.statusCode;
    final String status;
    if (code != null) {
      final message = call.statusMessage;
      status = message == null || message.isEmpty ? '$code' : '$code $message';
    } else {
      status = call.isPending ? strings.pendingStatus : strings.failedStatus;
    }
    final size = call.responseContentLength;
    final error = call.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (error != null) ...<Widget>[
          _ErrorCard(error: error, strings: strings),
          const SizedBox(height: 16),
        ],
        _InfoRow(
          label: strings.urlLabel,
          value: call.uri.toString(),
          strings: strings,
          copyable: true,
        ),
        _InfoRow(
          label: strings.methodLabel,
          value: call.method,
          strings: strings,
        ),
        _InfoRow(
          label: strings.statusLabel,
          value: status,
          strings: strings,
          valueColor: ApiCallStatusBadge.colorFor(call, Theme.of(context)),
        ),
        _InfoRow(
          label: strings.startedLabel,
          value: call.startedAt.toIso8601String(),
          strings: strings,
        ),
        _InfoRow(
          label: strings.durationLabel,
          value: call.durationLabel ?? strings.pendingStatus,
          strings: strings,
        ),
        _InfoRow(label: strings.hostLabel, value: call.host, strings: strings),
        _InfoRow(label: strings.pathLabel, value: call.path, strings: strings),
        _InfoRow(
          label: strings.secureLabel,
          value: call.isSecure ? strings.yes : strings.no,
          strings: strings,
        ),
        if (call.requestContentType != null)
          _InfoRow(
            label: strings.requestContentTypeLabel,
            value: call.requestContentType!,
            strings: strings,
          ),
        if (call.responseContentType != null)
          _InfoRow(
            label: strings.responseContentTypeLabel,
            value: call.responseContentType!,
            strings: strings,
          ),
        if (size != null)
          _InfoRow(
            label: strings.responseSizeLabel,
            value: ApiCallRecord.formatBytes(size),
            strings: strings,
          ),
      ],
    );
  }
}

class _RequestTab extends StatelessWidget {
  const _RequestTab({
    required this.call,
    required this.strings,
    required this.curlBuilder,
  });

  final ApiCallRecord call;
  final ApiInspectorStrings strings;
  final CurlCommandBuilder curlBuilder;

  @override
  Widget build(BuildContext context) {
    final query = call.uri.hasQuery ? _queryText(call.uri) : '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (query.isNotEmpty)
          _CodeSection(
            title: strings.queryParametersTitle,
            text: query,
            strings: strings,
          ),
        _CodeSection(
          title: strings.headersTitle,
          text: _headersText(call.requestHeaders),
          placeholder: strings.noHeaders,
          strings: strings,
        ),
        _CodeSection(
          title: strings.bodyTitle,
          text: call.requestBody ?? '',
          placeholder: strings.noBody,
          strings: strings,
        ),
        _CodeSection(
          title: strings.curlTitle,
          text: curlBuilder.build(call),
          strings: strings,
        ),
      ],
    );
  }

  static String _queryText(Uri uri) {
    try {
      return <String>[
        for (final entry in uri.queryParametersAll.entries)
          for (final value in entry.value) '${entry.key}: $value',
      ].join('\n');
    } on FormatException {
      return uri.query;
    }
  }
}

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.call, required this.strings});

  final ApiCallRecord call;
  final ApiInspectorStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (call.isPending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.hourglass_empty,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                strings.waitingForResponse,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    final error = call.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (error != null) ...<Widget>[
          _ErrorCard(error: error, strings: strings),
          const SizedBox(height: 16),
        ],
        _CodeSection(
          title: strings.headersTitle,
          text: _headersText(call.responseHeaders),
          placeholder: strings.noHeaders,
          strings: strings,
        ),
        _CodeSection(
          title: strings.bodyTitle,
          text: call.responseBody ?? '',
          placeholder: strings.noBody,
          strings: strings,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.strings,
    this.copyable = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final ApiInspectorStrings strings;
  final bool copyable;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: inspectorMonospaceStyle(context).copyWith(
                color: valueColor,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.content_copy),
              tooltip: strings.copyTooltip,
              onPressed: () => _copyText(context, value, strings),
            ),
        ],
      ),
    );
  }
}

class _CodeSection extends StatelessWidget {
  const _CodeSection({
    required this.title,
    required this.text,
    required this.strings,
    this.placeholder,
  });

  final String title;
  final String text;
  final String? placeholder;
  final ApiInspectorStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall),
              ),
              if (!empty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.content_copy),
                  tooltip: strings.copyTooltip,
                  onPressed: () => _copyText(context, text, strings),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.onSurface.withAlpha(12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: empty
                ? Text(
                    placeholder ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : SelectableText(text, style: inspectorMonospaceStyle(context)),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.strings});

  final String error;
  final ApiInspectorStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.errorTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: scheme.onErrorContainer,
                icon: const Icon(Icons.content_copy),
                tooltip: strings.copyTooltip,
                onPressed: () => _copyText(context, error, strings),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SelectableText(
              error,
              style: inspectorMonospaceStyle(context).copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
