import 'package:flutter/foundation.dart';

import '../domain/api_call_filter.dart';

/// User-facing texts of the API inspector UI (`ApiInspectorScreen`,
/// `ApiCallDetailScreen` and `SymphonyInspectorOverlay`).
///
/// Every value has an English default; pass your own values to localize:
///
/// ```dart
/// const strings = ApiInspectorStrings(
///   searchHint: 'Rechercher…',
///   emptyTitle: 'Aucun appel',
/// );
/// SymphonyInspectorOverlay(strings: strings, child: child!);
/// ```
@immutable
class ApiInspectorStrings {
  /// Creates the inspector texts.
  const ApiInspectorStrings({
    this.searchHint = 'Search method, URL, status…',
    this.clearSearchTooltip = 'Clear search',
    this.filterAll = 'All',
    this.filterSuccess = 'Success',
    this.filterClientError = '4xx',
    this.filterServerError = '5xx',
    this.filterFailed = 'Failed',
    this.filterPending = 'Pending',
    this.clearAllTooltip = 'Clear all calls',
    this.clearAllTitle = 'Clear all calls?',
    this.clearAllMessage =
        'Every captured call will be removed from the inspector.',
    this.clearAllConfirm = 'Clear',
    this.cancel = 'Cancel',
    this.pauseRecordingTooltip = 'Pause recording',
    this.resumeRecordingTooltip = 'Resume recording',
    this.recordingPaused = 'Recording is paused: new calls are not captured.',
    this.resumeRecording = 'Resume',
    this.emptyTitle = 'No API calls yet',
    this.emptyMessage =
        'Requests sent through the API client will appear here.',
    this.noMatchesTitle = 'No matching calls',
    this.noMatchesMessage = 'Try another search or status filter.',
    this.clearFilters = 'Clear filters',
    this.unavailableTitle = 'API inspector unavailable',
    this.unavailableMessage = 'Pass an ApiInspector to this screen or place '
        'it below a ProviderScope configured by SymphonyCore.',
    this.closeTooltip = 'Close',
    this.openInspectorLabel = 'Open API inspector',
    this.overviewTab = 'Overview',
    this.requestTab = 'Request',
    this.responseTab = 'Response',
    this.urlLabel = 'URL',
    this.methodLabel = 'Method',
    this.statusLabel = 'Status',
    this.startedLabel = 'Started',
    this.durationLabel = 'Duration',
    this.hostLabel = 'Host',
    this.pathLabel = 'Path',
    this.secureLabel = 'Secure',
    this.yes = 'Yes',
    this.no = 'No',
    this.requestContentTypeLabel = 'Request type',
    this.responseContentTypeLabel = 'Response type',
    this.responseSizeLabel = 'Response size',
    this.headersTitle = 'Headers',
    this.queryParametersTitle = 'Query parameters',
    this.bodyTitle = 'Body',
    this.noHeaders = 'No headers',
    this.noBody = 'No body',
    this.errorTitle = 'Error',
    this.pendingStatus = 'Pending',
    this.failedStatus = 'Failed',
    this.waitingForResponse = 'Waiting for the response…',
    this.copyTooltip = 'Copy',
    this.copiedMessage = 'Copied to clipboard',
    this.copyCurlTooltip = 'Copy as cURL',
    this.curlTitle = 'cURL',
  });

  /// Hint of the search field.
  final String searchHint;

  /// Tooltip of the button clearing the search field.
  final String clearSearchTooltip;

  /// Label of the [ApiCallStatusFilter.all] chip.
  final String filterAll;

  /// Label of the [ApiCallStatusFilter.success] chip.
  final String filterSuccess;

  /// Label of the [ApiCallStatusFilter.clientError] chip.
  final String filterClientError;

  /// Label of the [ApiCallStatusFilter.serverError] chip.
  final String filterServerError;

  /// Label of the [ApiCallStatusFilter.failed] chip.
  final String filterFailed;

  /// Label of the [ApiCallStatusFilter.pending] chip.
  final String filterPending;

  /// Tooltip of the clear-all button.
  final String clearAllTooltip;

  /// Title of the clear-all confirmation dialog.
  final String clearAllTitle;

  /// Message of the clear-all confirmation dialog.
  final String clearAllMessage;

  /// Confirmation button of the clear-all dialog.
  final String clearAllConfirm;

  /// Cancel button of dialogs.
  final String cancel;

  /// Tooltip of the button pausing the recording.
  final String pauseRecordingTooltip;

  /// Tooltip of the button resuming the recording.
  final String resumeRecordingTooltip;

  /// Banner shown while the recording is paused.
  final String recordingPaused;

  /// Action of the paused banner.
  final String resumeRecording;

  /// Title shown when no call was captured.
  final String emptyTitle;

  /// Message shown when no call was captured.
  final String emptyMessage;

  /// Title shown when the filters exclude every call.
  final String noMatchesTitle;

  /// Message shown when the filters exclude every call.
  final String noMatchesMessage;

  /// Action resetting the search and status filters.
  final String clearFilters;

  /// Title shown when no inspector can be found.
  final String unavailableTitle;

  /// Message shown when no inspector can be found.
  final String unavailableMessage;

  /// Tooltip of the close button of the overlay panel.
  final String closeTooltip;

  /// Accessibility label of the floating inspector button.
  final String openInspectorLabel;

  /// Title of the overview tab.
  final String overviewTab;

  /// Title of the request tab.
  final String requestTab;

  /// Title of the response tab.
  final String responseTab;

  /// Label of the URL row.
  final String urlLabel;

  /// Label of the method row.
  final String methodLabel;

  /// Label of the status row.
  final String statusLabel;

  /// Label of the start time row.
  final String startedLabel;

  /// Label of the duration row.
  final String durationLabel;

  /// Label of the host row.
  final String hostLabel;

  /// Label of the path row.
  final String pathLabel;

  /// Label of the "secure connection" row.
  final String secureLabel;

  /// Affirmative value.
  final String yes;

  /// Negative value.
  final String no;

  /// Label of the request content type row.
  final String requestContentTypeLabel;

  /// Label of the response content type row.
  final String responseContentTypeLabel;

  /// Label of the response size row.
  final String responseSizeLabel;

  /// Title of header sections.
  final String headersTitle;

  /// Title of the query parameters section.
  final String queryParametersTitle;

  /// Title of body sections.
  final String bodyTitle;

  /// Shown when a call has no headers.
  final String noHeaders;

  /// Shown when a call has no (captured) body.
  final String noBody;

  /// Title of error sections.
  final String errorTitle;

  /// Status text of calls in flight.
  final String pendingStatus;

  /// Status text of calls that failed without a response.
  final String failedStatus;

  /// Shown in the response tab of a call in flight.
  final String waitingForResponse;

  /// Tooltip of copy buttons.
  final String copyTooltip;

  /// Confirmation shown after copying.
  final String copiedMessage;

  /// Tooltip of the copy-as-cURL button.
  final String copyCurlTooltip;

  /// Title of the cURL section.
  final String curlTitle;

  /// Label of the chip for [status].
  String filterLabel(ApiCallStatusFilter status) {
    switch (status) {
      case ApiCallStatusFilter.all:
        return filterAll;
      case ApiCallStatusFilter.success:
        return filterSuccess;
      case ApiCallStatusFilter.clientError:
        return filterClientError;
      case ApiCallStatusFilter.serverError:
        return filterServerError;
      case ApiCallStatusFilter.failed:
        return filterFailed;
      case ApiCallStatusFilter.pending:
        return filterPending;
    }
  }
}
