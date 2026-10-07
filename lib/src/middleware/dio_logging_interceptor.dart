import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

/// Debug URLs, status codes and backend error bodies.
/// Omit credentials in request headers/bodies and successful response bodies.
class DioLoggingInterceptor extends PrettyDioLogger {
  DioLoggingInterceptor({void Function(Object)? logPrint})
      : super(
          enabled: kDebugMode,
          requestBody: false,
          requestHeader: false,
          responseBody: false,
          responseHeader: false,
          error: true,
          logPrint: logPrint ?? ((message) => debugPrint(message.toString())),
        );
}
