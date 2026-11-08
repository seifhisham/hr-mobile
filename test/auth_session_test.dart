import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/repositories/auth_repository_impl.dart';
import 'package:hodour/src/services/auth_service.dart';
import 'package:hodour/src/services/biometric_service.dart';
import 'package:hodour/src/ui/auth/providers/session_provider.dart';
import 'package:hodour/src/utils/failure.dart';

class TestBiometrics extends BiometricService {
  bool allowed = true;
  int attempts = 0;
  Completer<void>? pending;
  @override
  Future<void> authenticate() async {
    attempts++;
    if (pending != null) await pending!.future;
    if (!allowed) throw const BiometricFailure();
  }
}

class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object? body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

const profile = {
  'user': {
    'id': 'user-a',
    'name': 'Test Employee',
    'email': 'employee@example.test',
    'role': 'employee',
    'employeeId': 'employee-a'
  },
  'employee': {
    'id': 'employee-a',
    'employeeNumber': 'EMP-000001',
    'nationalId': '00123456789012',
    'name': 'Test Employee',
    'email': 'employee@example.test',
    'department': 'Engineering',
    'jobTitle': 'Engineer',
    'startDate': '2026-10-01',
    'scheduleId': 'schedule-a',
    'active': true,
    'monthlySalary': null
  },
  'company': {'name': 'Test Company', 'timezone': 'Africa/Cairo'},
  'today': '2026-10-06',
};
const schedules = [
  {
    'id': 'schedule-a',
    'name': 'Night shift',
    'start': '22:00',
    'end': '06:00',
    'days': [0, 1, 2, 3, 4],
    'graceMinutes': 15
  }
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio client;
  late AuthService auth;
  late TestBiometrics biometrics;
  final requests = <RequestOptions>[];
  var mode = 'ok';
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    mode = 'ok';
    requests.clear();
    client = Dio(BaseOptions(baseUrl: 'http://localhost:3002/api'));
    client.httpClientAdapter = TestAdapter((options) {
      requests.add(options);
      if (mode == 'offline') {
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionTimeout);
      }
      if (mode == 'expired' && !options.path.endsWith('/login')) {
        return jsonResponse({'message': 'Please sign in'}, 401);
      }
      if (options.path == '/auth/login') {
        if (mode == 'lockout') {
          return jsonResponse(
              {'message': 'Too many attempts. Try again in 15 minutes.'}, 429);
        }
        if (mode == 'invalid-login') {
          return jsonResponse({'message': 'Invalid email or password'}, 401);
        }
        return jsonResponse(
            {'token': 'opaque-test-token', 'user': profile['user']}, 201);
      }
      if (options.path == '/auth/me') return jsonResponse(profile);
      if (options.path == '/schedules') return jsonResponse(schedules);
      if (options.path == '/auth/password' && mode == 'wrong-password') {
        return jsonResponse({'message': 'Current password is incorrect'}, 401);
      }
      return jsonResponse({'message': 'Done'}, 201);
    });
    biometrics = TestBiometrics();
    auth = AuthService(client: client, biometrics: biometrics)..initialize();
  });
  tearDown(() {
    auth.dispose();
    client.close(force: true);
  });

  Future<void> login() async {
    final result = await auth.login(
        workspace: const String.fromEnvironment('TEST_WORKSPACE',
            defaultValue: 'test-company'),
        email: ' Employee@Example.Test ',
        password: ' password with spaces ');
    expect(result.isRight(), isTrue);
  }

  Future<String?> savedToken() =>
      const FlutterSecureStorage().read(key: AuthService.tokenKey);

  test(
      'login saves opaque token, loads exact profile/schedule and authenticates protected calls',
      () async {
    await login();
    expect(await savedToken(), 'opaque-test-token');
    expect(requests.first.data, {
      'workspace': 'test-company',
      'email': 'employee@example.test',
      'password': ' password with spaces ',
      'persistent': true
    });
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(requests[1].uri.path, '/api/auth/me');
    expect(requests[1].headers['Authorization'], 'Bearer opaque-test-token');
    final user = (await auth.getCurrentUser()).getOrElse((_) => null)!;
    expect(user.id, 'user-a');
    expect(user.employee!.id, 'employee-a');
    expect(user.employee!.nationalId, '00123456789012');
    expect(user.employee!.employeeNumber, 'EMP-000001');
    expect(user.timezone, 'Africa/Cairo');
    expect(user.today, '2026-10-06');
    expect(user.schedule!.end, '06:00');
    await client.get<void>('https://other.example.test/photo');
    expect(requests.last.headers.containsKey('Authorization'), isFalse);
  });
  test('startup restores token before /me; no token makes no request',
      () async {
    expect((await auth.getCurrentUser()).getOrElse((_) => null), isNull);
    expect(requests, isEmpty);
    FlutterSecureStorage.setMockInitialValues(
        {AuthService.tokenKey: 'restored-token'});
    final restored = await auth.getCurrentUser();
    expect(restored.isRight(), isTrue);
    expect(requests.first.headers['Authorization'], 'Bearer restored-token');
  });
  test('network outage blocks startup with retry state and retains saved token',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {AuthService.tokenKey: 'restored-token'});
    mode = 'offline';
    final session =
        SessionNotifier(repository: AuthRepositoryImpl(service: auth));
    addTearDown(session.dispose);
    await session.restore();
    expect(session.state, isA<SessionUnavailable>());
    expect(await savedToken(), 'restored-token');
    mode = 'ok';
    await session.restore();
    expect(session.state, isA<SessionAuthenticated>());
  });
  test('restart restores a token issued by persistent login', () async {
    await login();
    final restartedClient = Dio(BaseOptions(baseUrl: client.options.baseUrl))
      ..httpClientAdapter = TestAdapter((options) {
        expect(options.headers['Authorization'], 'Bearer opaque-test-token');
        return jsonResponse(options.path == '/auth/me' ? profile : schedules);
      });
    final restarted = AuthService(client: restartedClient)..initialize();
    addTearDown(restarted.dispose);
    addTearDown(() => restartedClient.close(force: true));
    expect((await restarted.getCurrentUser()).isRight(), isTrue);
  });
  test('server errors preserve token; protected 401 clears without retry',
      () async {
    await login();
    requests.clear();
    client.httpClientAdapter = TestAdapter((options) {
      requests.add(options);
      return jsonResponse({'message': 'Unavailable'}, 503);
    });
    expect((await auth.getCurrentUser()).isLeft(), isTrue);
    expect(await savedToken(), 'opaque-test-token');
    requests.clear();
    client.httpClientAdapter = TestAdapter((options) {
      requests.add(options);
      return jsonResponse({'message': 'Revoked'}, 401);
    });
    await expectLater(
        client.get<void>('/attendance'), throwsA(isA<DioException>()));
    expect(requests, hasLength(1));
    expect(await savedToken(), isNull);
  });
  test('opt-in requires biometric success and stores no password', () async {
    await login();
    biometrics.allowed = false;
    expect((await auth.setBiometricEnabled(true)).isLeft(), isTrue);
    expect(await auth.biometricEnabled(), isFalse);
    biometrics.allowed = true;
    expect((await auth.setBiometricEnabled(true)).isRight(), isTrue);
    expect(await auth.biometricEnabled(), isTrue);
    expect(await const FlutterSecureStorage().readAll(), {
      AuthService.tokenKey: 'opaque-test-token',
      BiometricService.enabledKey: 'true',
    });
    expect((await auth.setBiometricEnabled(false)).isRight(), isTrue);
    expect(await auth.biometricEnabled(), isFalse);
  });
  test(
      'locked startup sends no requests until biometric success; cancellation retains token',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      AuthService.tokenKey: 'restored-token',
      BiometricService.enabledKey: 'true',
    });
    biometrics.allowed = false;
    final result = await auth.getCurrentUser();
    expect(result.fold((failure) => failure, (_) => null),
        isA<BiometricFailure>());
    expect(requests, isEmpty);
    expect(await savedToken(), 'restored-token');
    biometrics.allowed = true;
    expect((await auth.getCurrentUser()).isRight(), isTrue);
    expect(requests.first.path, '/auth/me');
    expect(requests.first.headers['Authorization'], 'Bearer restored-token');
    await auth.getCurrentUser();
    expect(biometrics.attempts, 2);
  });
  test('locked logout revokes saved token and clears biometric preference',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      AuthService.tokenKey: 'restored-token',
      BiometricService.enabledKey: 'true',
    });
    expect((await auth.logout()).isRight(), isTrue);
    expect(requests.last.path, '/auth/logout');
    expect(requests.last.headers['Authorization'], 'Bearer restored-token');
    expect(await savedToken(), isNull);
    expect(await auth.biometricEnabled(), isFalse);
    expect(biometrics.attempts, 0);
  });
  test('revocation and password change remove biometric opt-in', () async {
    await login();
    await auth.setBiometricEnabled(true);
    mode = 'expired';
    await auth.getCurrentUser();
    expect(await auth.biometricEnabled(), isFalse);
    mode = 'ok';
    await login();
    await auth.setBiometricEnabled(true);
    await auth.changePassword(
        currentPassword: 'old', newPassword: 'new-password');
    expect(await auth.biometricEnabled(), isFalse);
    expect(await savedToken(), isNull);
  });
  test('logout during biometric prompt cannot restore old session', () async {
    FlutterSecureStorage.setMockInitialValues({
      AuthService.tokenKey: 'restored-token',
      BiometricService.enabledKey: 'true',
    });
    biometrics.pending = Completer<void>();
    final restoring = auth.getCurrentUser();
    while (biometrics.attempts == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await auth.logout();
    biometrics.pending!.complete();
    expect((await restoring).isLeft(), isTrue);
    expect(await savedToken(), isNull);
    expect(requests.where((r) => r.path == '/auth/me'), isEmpty);
  });
  test(
      'changing account clears the old token even when new credentials are rejected',
      () async {
    await login();
    mode = 'invalid-login';
    expect(
        (await auth.login(
                workspace: const String.fromEnvironment('TEST_WORKSPACE',
                    defaultValue: 'test-company'),
                email: 'employee@example.test',
                password: 'incorrect'))
            .isLeft(),
        isTrue);
    expect(await savedToken(), isNull);
    mode = 'ok';
    await login();
    mode = 'expired';
    final signedOut = auth.authStateChanges.first;
    final result = await auth.getCurrentUser();
    expect(result.isLeft(), isTrue);
    expect(await signedOut, isNull);
    expect(await savedToken(), isNull);
  });
  test(
      'foreground/profile refresh keeps authenticated access during outages and recovers',
      () async {
    await login();
    final session =
        SessionNotifier(repository: AuthRepositoryImpl(service: auth));
    addTearDown(session.dispose);
    await session.restore();
    mode = 'offline';
    await session.refresh();
    final current = session.state as SessionAuthenticated;
    expect(current.user.employee!.nationalId, '00123456789012');
    expect(current.profileRefresh.isFailure, isTrue);
    expect(await savedToken(), 'opaque-test-token');
    mode = 'ok';
    await session.refresh();
    expect((session.state as SessionAuthenticated).profileRefresh.isSuccess,
        isTrue);
  });
  test('wrong current password validates /me and preserves the session',
      () async {
    await login();
    mode = 'wrong-password';
    requests.clear();
    final result = await auth.changePassword(
        currentPassword: 'wrong', newPassword: 'new-password');
    expect(result.isLeft(), isTrue);
    expect(requests.map((request) => request.path),
        ['/auth/password', '/auth/me', '/schedules']);
    expect(await savedToken(), 'opaque-test-token');
    expect(requests.first.data,
        {'currentPassword': 'wrong', 'newPassword': 'new-password'});
  });
  test('password 401 followed by /me 401 invalidates session', () async {
    await login();
    mode = 'expired';
    final signedOut = auth.authStateChanges.first;
    expect(
        (await auth.changePassword(
                currentPassword: 'old', newPassword: 'new-password'))
            .isLeft(),
        isTrue);
    expect(await signedOut, isNull);
    expect(await savedToken(), isNull);
  });
  test('successful password change and logout remove local credentials',
      () async {
    await login();
    expect(
        (await auth.changePassword(
                currentPassword: 'old', newPassword: 'new-password'))
            .isRight(),
        isTrue);
    expect(await savedToken(), isNull);
    await login();
    expect((await auth.logout()).isRight(), isTrue);
    expect(requests.last.path, '/auth/logout');
    expect(requests.last.headers['Authorization'], 'Bearer opaque-test-token');
    expect(await savedToken(), isNull);
  });
  test(
      'offline logout clears local access and reports unconfirmed remote revocation',
      () async {
    await login();
    mode = 'offline';
    final signedOut = auth.authStateChanges.first;
    final result = await auth.logout();
    expect(result.isLeft(), isTrue);
    expect(result.fold((failure) => failure.message, (_) => ''),
        contains('could not be confirmed'));
    expect(await signedOut, isNull);
    expect(await savedToken(), isNull);
  });
  test(
      '429 is surfaced without automatic retry; NestJS arrays become readable messages',
      () async {
    mode = 'lockout';
    final result = await auth.login(
        workspace: const String.fromEnvironment('TEST_WORKSPACE',
            defaultValue: 'test-company'),
        email: 'employee@example.test',
        password: 'incorrect');
    expect(requests.length, 1);
    expect(
        result.fold(
            (failure) => (failure as ServerFailure).statusCode, (_) => null),
        429);
    expect(result.fold((failure) => failure.message, (_) => ''),
        contains('15 minutes'));
    final failure = Failure.fromException(DioException(
        requestOptions: RequestOptions(),
        response:
            Response(requestOptions: RequestOptions(), statusCode: 400, data: {
          'message': ['Invalid email', 'Password required']
        })));
    expect(failure.message, 'Invalid email\nPassword required');
  });
  test('late old-account response cannot restore profile after logout',
      () async {
    await login();
    final pending = Completer<ResponseBody>();
    final started = Completer<void>();
    client.httpClientAdapter = TestAdapter((options) {
      if (options.path == '/auth/me') {
        started.complete();
        return pending.future;
      }
      return jsonResponse({'message': 'Done'}, 201);
    });
    final oldResponse = auth.getCurrentUser();
    await started.future;
    await auth.logout();
    pending.complete(jsonResponse(profile));
    expect((await oldResponse).isLeft(), isTrue);
    expect(await savedToken(), isNull);
  });
  test('logout clears local session before remote revocation completes',
      () async {
    await login();
    final started = Completer<void>();
    final response = Completer<ResponseBody>();
    client.httpClientAdapter = TestAdapter((options) {
      if (options.path == '/auth/logout') {
        started.complete();
        return response.future;
      }
      return jsonResponse(profile);
    });
    final signedOut = auth.authStateChanges.first;
    final pending = auth.logout();
    await started.future;
    expect(await signedOut, isNull);
    expect(await savedToken(), isNull);
    expect((await auth.getCurrentUser()).fold((_) => 'failure', (user) => user),
        isNull);
    response.complete(jsonResponse({'message': 'Signed out'}, 201));
    expect((await pending).isRight(), true);
  });
  test('queued report cannot pick up a changed session token', () async {
    await login();
    final revision = auth.sessionRevision;
    final started = Completer<void>();
    final release = Completer<void>();
    client.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) async {
      if (options.path.endsWith('/location')) {
        started.complete();
        await release.future;
      }
      handler.next(options);
    }));
    final report = client.post<void>('/attendance/old-record/location',
        data: {'available': false},
        options: Options(extra: {'expectedSessionRevision': revision}));
    final rejected = expectLater(
        report,
        throwsA(isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)));
    await started.future;
    await auth.logout();
    await login();
    release.complete();
    await rejected;
    expect(requests.where((request) => request.path.endsWith('/location')),
        isEmpty);
  });
}
