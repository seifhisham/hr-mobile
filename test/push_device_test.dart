import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hodour/src/services/auth_service.dart';
import 'package:hodour/src/services/push_device_service.dart';
import 'auth_session_test.dart'
    show TestAdapter, jsonResponse, profile, schedules;

Future<void> flushPush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio client;
  late AuthService auth;
  late PushDeviceService push;
  final calls = <RequestOptions>[];
  var status = 200;
  var session = 0;
  var retryAfter = '1';
  var company = 'company-a';
  Future<ResponseBody> Function(RequestOptions)? held;
  const firstToken = 'test-fcm-registration-token-one';
  const secondToken = 'test-fcm-registration-token-two';
  Future<void> login() async {
    expect(
        (await auth.login(
                workspace: 'test-company',
                email: 'test@example.test',
                password: 'test-password'))
            .isRight(),
        true);
    await flushPush();
  }

  List<RequestOptions> getPosts() => calls
      .where((r) => r.path == '/push/devices' && r.method == 'POST')
      .toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    calls.clear();
    held = null;
    status = 200;
    session = 0;
    retryAfter = '1';
    company = 'company-a';
    client = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    client.httpClientAdapter = TestAdapter((r) {
      calls.add(r);
      if (r.path == '/auth/login') {
        return jsonResponse({'token': 'session-${++session}'}, 201);
      }
      if (r.path == '/auth/me') {
        return jsonResponse({
          ...profile,
          'company': {
            ...profile['company'] as Map<String, Object?>,
            'id': company
          },
        });
      }
      if (r.path == '/schedules') return jsonResponse(schedules);
      if (r.path == '/push/devices') {
        if (held != null) return held!(r);
        if (status == 429) {
          return ResponseBody.fromString('{}', 429, headers: {
            'retry-after': [retryAfter]
          });
        }
        return jsonResponse({}, status);
      }
      if (r.path.startsWith('/push/devices/')) return jsonResponse(null, 204);
      return jsonResponse({});
    });
    push = PushDeviceService(client: client, enabled: true);
    auth = AuthService(client: client, pushDevices: push)..initialize();
  });
  tearDown(() {
    auth.dispose();
    push.dispose();
    client.close(force: true);
  });

  test('login waits for FCM, rotates tokens, and keeps installation UUID',
      () async {
    await login();
    expect(getPosts(), isEmpty);
    await push.tokenChanged(firstToken);
    await flushPush();
    final first = getPosts().single;
    expect(first.headers['Authorization'], 'Bearer session-1');
    expect(first.data.keys.toSet(), {'deviceId', 'token', 'platform'});
    expect(first.data['platform'], 'android');
    final id = first.data['deviceId'];
    expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    await push.tokenChanged(secondToken);
    await flushPush();
    expect(getPosts().last.data['token'], secondToken);
    expect(getPosts().last.data['deviceId'], id);
    final another = PushDeviceService(client: client, enabled: true);
    addTearDown(another.dispose);
    expect(await another.installationId(), id);
  });

  test('authenticated restoration registers saved FCM token', () async {
    FlutterSecureStorage.setMockInitialValues({
      AuthService.tokenKey: 'restored-session',
      PushDeviceService.tokenKey: firstToken,
    });
    expect((await auth.getCurrentUser()).isRight(), true);
    await flushPush();
    expect(
        getPosts().single.headers['Authorization'], 'Bearer restored-session');
    expect(getPosts().single.data['token'], firstToken);
  });

  test(
      'logout deletes with old session before auth logout and credential removal',
      () async {
    await push.tokenChanged(firstToken);
    await login();
    expect((await auth.logout()).isRight(), true);
    final deletion = calls.indexWhere((r) => r.method == 'DELETE');
    final logout = calls.indexWhere((r) => r.path == '/auth/logout');
    expect(deletion, greaterThan(-1));
    expect(deletion, lessThan(logout));
    expect(calls[deletion].headers['Authorization'], 'Bearer session-1');
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        isNull);
    await push.tokenChanged(secondToken);
    await flushPush();
    expect(getPosts().length, 1);
  });

  test('old in-flight POST finishes before a new-session transfer', () async {
    final response = Completer<ResponseBody>();
    held = (_) => response.future;
    await push.tokenChanged(firstToken);
    await login();
    expect(getPosts().length, 1);
    company = 'company-b';
    await login();
    expect(getPosts().length, 1);
    held = null;
    response.complete(jsonResponse({}));
    await flushPush();
    expect(getPosts().length, 2);
    expect(getPosts().last.headers['Authorization'], 'Bearer session-2');
  });

  test('temporary failure retries and succeeds without another login',
      () async {
    status = 503;
    await push.tokenChanged(firstToken);
    await login();
    expect(getPosts().length, 1);
    status = 200;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(getPosts().length, 2);
  });

  test('retry budget is bounded and exhausted work retries on resume',
      () async {
    status = 503;
    await push.tokenChanged(firstToken);
    await login();
    await Future<void>.delayed(const Duration(seconds: 16));
    expect(getPosts().length, 3);
    status = 200;
    push.resume();
    await flushPush();
    expect(getPosts().length, 4);
  });

  test('logout cancels scheduled retries', () async {
    status = 503;
    await push.tokenChanged(firstToken);
    await login();
    await auth.logout();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(getPosts().length, 1);
  });

  test('429 honors Retry-After even on resume or token rotation', () async {
    status = 429;
    retryAfter = '60';
    await push.tokenChanged(firstToken);
    await login();
    push.resume();
    await push.tokenChanged(secondToken);
    await flushPush();
    expect(getPosts().length, 1);
  });

  test('401 stops retries until a newly authenticated session', () async {
    status = 401;
    await push.tokenChanged(firstToken);
    await login();
    push.resume();
    await push.tokenChanged(secondToken);
    await flushPush();
    expect(getPosts().length, 1);
    status = 200;
    await login();
    expect(getPosts().length, 2);
  });

  test('failed device deletion cannot prevent local logout', () async {
    await push.tokenChanged(firstToken);
    await login();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      if (r.method == 'DELETE') {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        h.next(r);
      }
    }));
    await auth.logout();
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        isNull);
    expect(calls.any((r) => r.path == '/auth/logout'), true);
  });
}
