import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/utils.dart';
import 'secure_storage_service.dart';

/// Serializes installation transfers; an old POST must finish before a new one.
class PushDeviceService {
  PushDeviceService({Dio? client, bool? enabled})
      : _client = client,
        enabled = enabled ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  static final instance = PushDeviceService();
  final Dio? _client;
  final bool enabled;
  Dio get _dio => _client ?? AppConfig.dio;
  static const deviceKey = 'push_installation_id';
  static const tokenKey = 'push_registration_token';
  Future<String>? _device;
  Future<void> _work = Future.value();
  Future<void> _tokenWork = Future.value();
  Timer? _retry;
  int _generation = 0;
  int? _revision;
  Object? _identity;
  String? _token;
  bool _pending = false;
  bool _blocked = false;
  bool _hasBinding = false;
  int _attempts = 0;
  DateTime? _notBefore;

  Future<String> installationId() => _device ??= () async {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(deviceKey);
        if (saved != null) return saved;
        final random = Random.secure();
        final bytes = List.generate(16, (_) => random.nextInt(256));
        bytes[6] = (bytes[6] & 15) | 64;
        bytes[8] = (bytes[8] & 63) | 128;
        final hex =
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
            '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
        if (!await prefs.setString(deviceKey, id)) {
          throw StateError('Unable to persist installation ID');
        }
        return id;
      }();

  void sessionChanged(int? revision, [Object? identity]) {
    if (!enabled || (_revision == revision && _identity == identity)) return;
    _generation++;
    _retry?.cancel();
    _revision = revision;
    _identity = identity;
    _blocked = false;
    _pending = revision != null;
    _attempts = 0;
    if (_pending) resume();
  }

  Future<void> tokenChanged(String token) async {
    if (!enabled || token == _token) return;
    _token = token;
    _generation++;
    _retry?.cancel();
    _pending = _revision != null;
    _attempts = 0;
    _tokenWork = _tokenWork.then((_) async {
      await SecureStorageService.instance.write(tokenKey, token);
    });
    await _tokenWork;
    resume();
  }

  void resume() {
    if (!enabled || !_pending || _revision == null || _blocked) return;
    _retry?.cancel();
    final delay = _notBefore?.difference(DateTime.now());
    if (delay != null && delay > Duration.zero) {
      _retry = Timer(delay, resume);
      return;
    }
    _attempts = 0;
    _enqueue(_generation);
  }

  void _enqueue(int generation) {
    _work = _work.then((_) => _register(generation));
  }

  Future<void> _register(int generation) async {
    if (generation != _generation ||
        !_pending ||
        _revision == null ||
        _blocked) {
      return;
    }
    final wait = _notBefore?.difference(DateTime.now());
    if (wait != null && wait > Duration.zero) {
      _retry?.cancel();
      _retry = Timer(wait, () => _enqueue(generation));
      return;
    }
    int? status;
    Duration? retryAfter;
    _attempts++;
    final result = await runTask(() async {
      final token = _token ??
          await SecureStorageService.instance
              .read(tokenKey)
              .then((r) => r.fold((f) => throw f, (v) => v));
      if (token == null) return false;
      final device = await installationId();
      if (generation != _generation) return false;
      _hasBinding = true;
      try {
        await _dio.post<void>('/push/devices',
            data: {
              'deviceId': device,
              'token': token,
              'platform': 'android',
            },
            options: Options(
                extra: {'expectedSessionRevision': _revision},
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5)));
        return true;
      } on DioException catch (error) {
        status = error.response?.statusCode;
        final seconds =
            int.tryParse(error.response?.headers.value('retry-after') ?? '');
        if (seconds != null) retryAfter = Duration(seconds: max(0, seconds));
        rethrow;
      }
    }, operation: 'push.register', category: LogCategory.network);
    if (generation != _generation) return;
    result.fold((_) {
      if (status == 401 || status == 400 || status == 403) {
        _blocked = true;
        return;
      }
      final temporary = status == null || status == 429 || status! >= 500;
      if (!temporary) return;
      final backoff = Duration(
          milliseconds:
              1000 * (1 << min(_attempts, 3)) + Random().nextInt(500));
      final delay =
          retryAfter != null && retryAfter! > backoff ? retryAfter! : backoff;
      _notBefore = DateTime.now().add(delay);
      if (_attempts < 3) {
        _retry = Timer(delay, () => _enqueue(generation));
      }
    }, (registered) {
      if (registered) {
        _pending = false;
        _notBefore = null;
      }
    });
  }

  Future<void> unregister(int revision) async {
    if (!enabled) return;
    final hadBinding = _hasBinding;
    sessionChanged(null);
    if (!hadBinding) return;
    final work = _work.then((_) async {
      await runTask(() async {
        final device = await installationId();
        await _dio.delete<void>('/push/devices/$device',
            options: Options(
                extra: {'expectedSessionRevision': revision},
                sendTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 3)));
      }, operation: 'push.unregister', category: LogCategory.network);
    });
    _work = work;
    await work;
  }

  void dispose() {
    _generation++;
    _retry?.cancel();
    _revision = null;
  }
}
