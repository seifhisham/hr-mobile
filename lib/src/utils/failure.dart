import 'package:equatable/equatable.dart';
import 'package:dio/dio.dart';

import 'error_handler.dart';

/// Domain-level failure hierarchy. Prefer exhaustive `switch` over `is` checks.
sealed class Failure extends Equatable {
  const Failure(this.message, {this.error});

  final String message;
  final Object? error;

  /// Maps thrown objects into a typed [Failure] for railway-style APIs.
  factory Failure.fromException(Object error, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == null) {
        return NetworkFailure(
          'Unable to connect to the server. Please try again.',
          error: error,
        );
      }
      final body = error.response?.data;
      final message = body is Map ? body['message'] : null;
      final safeMessage = status >= 500
          ? 'The service is unavailable. Please try again.'
          : switch (message) {
              final String text when text.isNotEmpty => text,
              final List<Object?> messages =>
                messages.whereType<String>().join('\n'),
              _ => 'The request could not be completed.',
            };
      return ServerFailure(safeMessage, statusCode: status, error: error);
    }
    if (error is FormatException || error is TypeError) {
      return const ServerFailure('The server returned an invalid response.');
    }

    final message = AppErrorHandler.format(error);
    return switch (error) {
      final Exception e
          when e.toString().contains('SocketException') ||
              e.toString().contains('Network') =>
        NetworkFailure(message, error: error),
      _ => UnknownFailure(message, error: error),
    };
  }

  @override
  List<Object?> get props => [message, error];

  @override
  String toString() => message;
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.statusCode, super.error});
  final int? statusCode;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

final class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.error});
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.error});
}

final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.error});
}

enum CaptureRecovery { retry, appSettings, locationSettings }

final class CaptureFailure extends Failure {
  const CaptureFailure(super.message, {this.recovery = CaptureRecovery.retry});
  final CaptureRecovery recovery;
}
