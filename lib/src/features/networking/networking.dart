/// Networking: the central Dio based `ApiClient`, its interceptors, error
/// mapping and contracts.
///
/// The Dio types that appear in public signatures (requests, interceptors,
/// adapters, multipart bodies...) are re-exported so applications can write
/// interceptors and adapters without importing `package:dio` themselves.
/// Note that Dio's `Response` type is re-exported: hide it
/// (`import 'package:symphony_core/symphony_core.dart' hide Response;`) if the
/// application also imports `package:http`.
library;

export 'package:dio/dio.dart'
    show
        CancelToken,
        Dio,
        DioException,
        DioExceptionType,
        ErrorInterceptorHandler,
        FormData,
        Headers,
        HttpClientAdapter,
        Interceptor,
        InterceptorsWrapper,
        MultipartFile,
        Options,
        ProgressCallback,
        QueuedInterceptor,
        QueuedInterceptorsWrapper,
        RequestInterceptorHandler,
        RequestOptions,
        Response,
        ResponseBody,
        ResponseInterceptorHandler,
        ResponseType;

export 'data/api_client.dart';
export 'data/default_api_error_mapper.dart';
export 'data/interceptors/auth_token_interceptor.dart';
export 'data/interceptors/headers_interceptor.dart';
export 'data/interceptors/retry_interceptor.dart';
export 'data/interceptors/secure_logging_interceptor.dart';
export 'data/upload_form_data.dart';
export 'domain/api_error_mapper.dart';
export 'domain/api_request_options.dart';
export 'domain/api_response.dart';
export 'domain/auth_token_delegate.dart';
export 'domain/upload_file.dart';
export 'presentation/networking_providers.dart';
