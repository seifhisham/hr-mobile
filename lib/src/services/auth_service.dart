import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import '../config/app_config.dart';
import '../data/models/user_model.dart';
import '../utils/utils.dart';
import 'secure_storage_service.dart';

class AuthService {
  AuthService({Dio? client}) : _client = client;
  static final AuthService instance = AuthService();
  static const tokenKey = 'session_token';
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;
  final _storage = SecureStorageService.instance;
  final _changes = StreamController<AppUser?>.broadcast();
  String? _token;
  int _revision = 0;
  Stream<AppUser?> get authStateChanges => _changes.stream;

  /// Install once on the shared client before authenticated requests.
  void initialize() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null &&
            options.uri.origin == Uri.parse(_dio.options.baseUrl).origin &&
            !options.uri.path.endsWith('/auth/login')) {
          options.headers['Authorization'] = 'Bearer $_token';
          options.extra['sessionRevision'] = _revision;
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final path = error.requestOptions.uri.path;
        if (error.response?.statusCode == 401 &&
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
        handler.next(error);
      },
    ));
  }

  FutureEither<AppUser> login(
          {required String email, required String password}) =>
      runTask(() async {
        final response = await _dio.post<Map<String, dynamic>>('/auth/login',
            data: {'email': email.trim().toLowerCase(), 'password': password});
        final token = response.data?['token'];
        if (token is! String || token.isEmpty) {
          throw const FormatException('Missing session token');
        }
        await _storage.write(tokenKey, token).then(_unwrap);
        _token = token;
        _revision++;
        final user = await _loadProfile();
        _changes.add(user);
        return user;
      }, operation: 'auth.login', category: LogCategory.auth);

  FutureEither<AppUser?> getCurrentUser() => runTask(() async {
        final revision = _revision;
        if (_token == null) {
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
    return AppUser.fromJson(json, schedule: schedule);
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
        try {
          if (_token != null) await _dio.post<void>('/auth/logout');
        } on DioException {
          throw const NetworkFailure(
              'Signed out on this device. Server sign-out could not be confirmed.');
        } finally {
          await _clearSession();
        }
      }, operation: 'auth.logout', category: LogCategory.auth);

  Future<void> _clearSession() async {
    _token = null;
    _revision++;
    _changes.add(null);
    await _storage.delete(tokenKey).then(_unwrap);
  }

  void dispose() => _changes.close();
}

T _unwrap<T>(Either<Failure, T> result) =>
    result.fold((failure) => throw failure, (value) => value);
