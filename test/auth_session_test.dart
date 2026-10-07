import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmobile/src/data/repositories/auth_repository_impl.dart';
import 'package:hrmobile/src/services/auth_service.dart';
import 'package:hrmobile/src/ui/auth/providers/session_provider.dart';
import 'package:hrmobile/src/utils/failure.dart';

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
    auth = AuthService(client: client)..initialize();
  });
  tearDown(() {
    auth.dispose();
    client.close(force: true);
  });

  Future<void> login() async {
    final result = await auth.login(
        email: ' Employee@Example.Test ', password: ' password with spaces ');
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
      'email': 'employee@example.test',
      'password': ' password with spaces '
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
  test(
      'protected 401 clears secure token and session; login 401 does not clear an existing session',
      () async {
    await login();
    mode = 'invalid-login';
    expect(
        (await auth.login(
                email: 'employee@example.test', password: 'incorrect'))
            .isLeft(),
        isTrue);
    expect(await savedToken(), 'opaque-test-token');
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
    final result =
        await auth.login(email: 'employee@example.test', password: 'incorrect');
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
}
