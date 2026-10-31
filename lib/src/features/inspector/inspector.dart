/// Custom API inspector: captures HTTP traffic and displays it in-app.
///
/// * [ApiInspector] stores redacted calls; [ApiInspectorInterceptor] feeds it
///   from Dio; `apiInspectorProvider` exposes the shared instance.
/// * [ApiInspectorScreen] / [showApiInspector] display the calls,
///   [ApiCallDetailScreen] shows one call and [SymphonyInspectorOverlay] adds
///   a floating entry point to any app.
/// * [ApiCallFilter] and [CurlCommandBuilder] are pure helpers.
library;

export 'data/api_inspector.dart';
export 'data/api_inspector_interceptor.dart';
export 'domain/api_call_filter.dart';
export 'domain/api_call_form_data.dart';
export 'domain/api_call_record.dart';
export 'domain/curl_command_builder.dart';
export 'presentation/api_inspector_strings.dart';
export 'presentation/inspector_providers.dart';
export 'presentation/screens/api_call_detail_screen.dart';
export 'presentation/screens/api_inspector_screen.dart';
export 'presentation/widgets/api_call_tile.dart';
export 'presentation/widgets/symphony_inspector_overlay.dart';
