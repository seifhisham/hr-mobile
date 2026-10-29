import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import '../config/app_config.dart';
import '../data/models/user_model.dart';
import '../utils/utils.dart';
import 'secure_storage_service.dart';
import 'push_device_service.dart';

class AuthService {
  AuthService({Dio? client, PushDeviceService? pushDevices})
      : _client = client,
        _pushDevices = pushDevices;
  final PushDeviceService? _pushDevices;
  PushDeviceService get _push => _pushDevices ?? PushDeviceService.instance;
  static final AuthService instance = AuthService();
  static const tokenKey = 'session_token';
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;
  final _storage = SecureStorageService.instance;
  final _changes = StreamController<AppUser?>.broadcast();
  String? _token;
  int _revision = 0;
  Future<void> _storageWork = Future.value();

  Future<void> _persist(FutureEither<void> Function() action) {
    final work = _storageWork.then((_) async {
      await action().then(_unwrap);
    });
    // The caller receives the failure; later cleanup must still run.
    _storageWork = work.catchError((Object _) {
      AppLogger.warning('Secure session storage operation failed',
          category: LogCategory.auth);
    });
    return work;
  }

  int get sessionRevision => _revision;
  Stream<AppUser?> get authStateChanges => _changes.stream;

  /// Install once on the shared client before authenticated requests.
  void initialize() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final expectedRevision = options.extra['expectedSessionRevision'];
        if (expectedRevision != null && expectedRevision != _revision) {
          handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'Session changed'));
          return;
        }
        if (_token != null &&
            options.uri.origin == Uri.parse(_dio.options.baseUrl).origin &&
            !options.uri.path.endsWith('/auth/login')) {
          options.headers['Authorization'] = 'Bearer $_token';
          options.extra['sessionRevision'] = _revision;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final revision = response.requestOptions.extra['sessionRevision'];
        if (revision != null && revision != _revision) {
          handler.reject(DioException(
              requestOptions: response.requestOptions,
              type: DioExceptionType.cancel,
              message: 'Session changed'));
          return;
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        final path = error.requestOptions.uri.path;
        if ((error.response?.statusCode == 401 ||
                error.response?.statusCode == 403 &&
                    path.endsWith('/auth/me')) &&
            !path.endsWith('/auth/login') &&
            !path.endsWith('/auth/password') &&
            error.requestOptions.extra['sessionRevision'] == _revision) {
          try {
            await _clearSession();
          } catch (failure) {
            AppLogger.error('Unable to remove saved session',
                error: failure.runtimeType.toString(),
                category: LogCategory.auth);
          }
        }
        if (error.response?.statusCode == 403 &&
            !path.endsWith('/auth/login') &&
            !path.endsWith('/auth/me') &&
            error.requestOptions.extra['sessionRevision'] == _revision) {
          // Permission failures alone do not imply expiry. /me checks access.
          await runTask(() => _dio.get<Map<String, dynamic>>('/auth/me'),
              operation: 'auth.validate', category: LogCategory.auth);
        }
        handler.next(error);
      },
    ));
  }

  FutureEither<AppUser> login(
          {required String workspace,
          required String email,
          required String password}) =>
      runTask(() async {
        final code = workspace.trim().toLowerCase();
        if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,62}$').hasMatch(code)) {
          throw const ServerFailure(
              'Enter a valid company code (2–63 lowercase letters, digits or hyphens).');
        }
        final clearing = _clearSession();
        final revision = _revision;
        await clearing;
        if (revision != _revision) {
          throw const ServerFailure('Session changed', statusCode: 401);
        }
        final response = await _dio.post<Map<String, dynamic>>('/auth/login',
            data: {
              'workspace': code,
              'email': email.trim().toLowerCase(),
              'password': password
            });
        if (revision != _revision) {
          throw const ServerFailure('Session changed', statusCode: 401);
        }
        final token = response.data?['token'];
        if (token is! String || token.isEmpty) {
          throw const FormatException('Missing session token');
        }
        await _persist(() => _storage.write(tokenKey, token));
        if (revision != _revision) {
          throw const ServerFailure('Session changed', statusCode: 401);
        }
        _token = token;
        _revision++;
        final user = await _loadProfile();
        _changes.add(user);
        return user;
      }, operation: 'auth.login', category: LogCategory.auth);

  FutureEither<AppUser?> getCurrentUser() => runTask(() async {
        final revision = _revision;
        if (_token == null) {
          await _storageWork;
          if (revision != _revision) return null;
          final saved = await _storage.read(tokenKey).then(_unwrap);
          if (revision != _revision) return null;
          _token = saved;
        }
        if (_token == null) return null;
        return _loadProfile();
      }, operation: 'auth.restore', category: LogCategory.auth);

  Future<AppUser> _loadProfile() async {
    final revision = _revision;
    final response = await _dio.get<Map<String, dynamic>>('/auth/me');
    if (_token == null || revision != _revision) {
      throw const ServerFailure('Please sign in again.', statusCode: 401);
    }
    final json = response.data;
    if (json == null) throw const FormatException('Missing session');
    final user = AppUser.fromJson(json);
    WorkSchedule? schedule;
    final scheduleId = user.employee?.scheduleId;
    if (scheduleId != null) {
      final schedules = await _dio.get<List<dynamic>>('/schedules');
      for (final item in schedules.data ?? []) {
        final data = item as Map<String, dynamic>;
        if (data['id'] == scheduleId) {
          schedule = WorkSchedule.fromJson(data);
          break;
        }
      }
    }
    if (_token == null || revision != _revision) {
      throw const ServerFailure('Please sign in again.', statusCode: 401);
    }
    final profile = AppUser.fromJson(json, schedule: schedule);
    _push.sessionChanged(_revision, profile.sessionIdentity);
    return profile;
  }

  FutureEither<void> changePassword(
          {required String currentPassword, required String newPassword}) =>
      runTask(() async {
        try {
          await _dio.post<void>('/auth/password', data: {
            'currentPassword': currentPassword,
            'newPassword': newPassword
          });
        } on DioException catch (error) {
          if (error.response?.statusCode == 401) {
            // Wrong current password is also 401; /me checks actual session validity.
            await getCurrentUser();
          }
          rethrow;
        }
        await _clearSession();
      }, operation: 'auth.changePassword', category: LogCategory.auth);

  FutureEither<void> logout() => runTask(() async {
        final token = _token;
        final previousRevision = _revision;
        if (token != null) {
          try {
            await _push
                .unregister(previousRevision)
                .timeout(const Duration(seconds: 5));
          } on TimeoutException {
            AppLogger.warning('Push unregister timed out');
          }
          if (previousRevision != _revision) return;
        }
        // End local tracking/access before waiting for remote revocation.
        final clearing = _clearSession();
        final revision = _revision;
        await clearing;
        try {
          if (token != null) {
            await _dio.post<void>('/auth/logout',
                options: Options(
                    headers: {'Authorization': 'Bearer $token'},
                    extra: {'expectedSessionRevision': revision}));
          }
        } on DioException {
          throw const NetworkFailure(
              'Signed out on this device. Server sign-out could not be confirmed.');
        }
      }, operation: 'auth.logout', category: LogCategory.auth);

  Future<void> _clearSession() async {
    _push.sessionChanged(null);
    _token = null;
    _revision++;
    _changes.add(null);
    await _persist(() => _storage.delete(tokenKey));
  }

  void dispose() {
    _push.sessionChanged(null);
    _changes.close();
  }
}

T _unwrap<T>(Either<Failure, T> result) =>
    result.fold((failure) => throw failure, (value) => value);
