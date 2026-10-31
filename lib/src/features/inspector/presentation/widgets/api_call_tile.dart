import 'package:flutter/material.dart';

import '../../domain/api_call_record.dart';
import '../api_inspector_strings.dart';

/// Monospace text style used by the inspector for code-like content.
TextStyle inspectorMonospaceStyle(BuildContext context, {double? fontSize}) {
  final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
  return base.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const <String>['Menlo', 'Consolas', 'Courier New'],
    fontSize: fontSize ?? 12.5,
    height: 1.35,
  );
}

/// Colored badge showing an HTTP [method] (GET, POST...).
class ApiCallMethodBadge extends StatelessWidget {
  /// Creates a method badge.
  const ApiCallMethodBadge({super.key, required this.method});

  /// HTTP method.
  final String method;

  /// Color associated with [method] for the given [brightness].
  static Color colorFor(String method, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (method.toUpperCase()) {
      case 'GET':
        return dark ? Colors.lightBlue.shade200 : Colors.blue.shade700;
      case 'POST':
        return dark ? Colors.green.shade300 : Colors.green.shade800;
      case 'PUT':
        return dark ? Colors.orange.shade300 : Colors.orange.shade900;
      case 'PATCH':
        return dark ? Colors.purple.shade200 : Colors.purple.shade700;
      case 'DELETE':
        return dark ? Colors.red.shade300 : Colors.red.shade700;
      default:
        return dark ? Colors.blueGrey.shade200 : Colors.blueGrey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(method, Theme.of(context).brightness);
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Text(
        method.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 1,
        style: inspectorMonospaceStyle(context, fontSize: 11.5).copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Badge showing the outcome of a call: a spinner while pending, the status
/// code colored by class (2xx, 3xx, 4xx, 5xx) or a "failed" label.
class ApiCallStatusBadge extends StatelessWidget {
  /// Creates a status badge.
  const ApiCallStatusBadge({
    super.key,
    required this.record,
    this.strings = const ApiInspectorStrings(),
  });

  /// The call.
  final ApiCallRecord record;

  /// Texts (the "failed" label).
  final ApiInspectorStrings strings;

  /// Color describing the outcome of [record].
  static Color colorFor(ApiCallRecord record, ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final code = record.statusCode;
    if (record.isPending) return theme.colorScheme.outline;
    if (code == null) return theme.colorScheme.error;
    if (code >= 500) return dark ? Colors.red.shade300 : Colors.red.shade700;
    if (code >= 400) {
      return dark ? Colors.orange.shade300 : Colors.deepOrange.shade700;
    }
    if (code >= 300) {
      return dark ? Colors.lightBlue.shade200 : Colors.blue.shade700;
    }
    if (code >= 200 && !record.isError) {
      return dark ? Colors.green.shade300 : Colors.green.shade800;
    }
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    if (record.isPending) {
      return Semantics(
        label: strings.pendingStatus,
        child: const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final theme = Theme.of(context);
    final color = colorFor(record, theme);
    final code = record.statusCode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        code == null ? strings.failedStatus : '$code',
        maxLines: 1,
        style: inspectorMonospaceStyle(context, fontSize: 12).copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// List item describing one captured call: method, path, host, time,
/// duration and status.
class ApiCallTile extends StatelessWidget {
  /// Creates a tile.
  const ApiCallTile({
    super.key,
    required this.record,
    this.onTap,
    this.strings = const ApiInspectorStrings(),
  });

  /// The call.
  final ApiCallRecord record;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  /// Texts.
  final ApiInspectorStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final details = <String>[
      record.timeLabel,
      record.durationLabel ?? strings.pendingStatus,
    ].join('  ·  ');
    final error = record.error;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ApiCallMethodBadge(method: record.method),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      if (record.isSecure) ...<Widget>[
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          record.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(details, maxLines: 1, style: secondary),
                  if (error != null && record.statusCode == null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      error,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            ApiCallStatusBadge(record: record, strings: strings),
          ],
        ),
      ),
    );
  }
}
