import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/data/models/user_model.dart';
import 'package:hodour/src/services/auth_service.dart';
import 'package:hodour/src/ui/auth/providers/session_provider.dart';
import 'package:hodour/src/ui/attendance/attendance_provider.dart';
import 'package:hodour/src/imports/imports.dart' show ProviderContainer;
import 'package:hodour/src/data/repositories/auth_repository_impl.dart';
import 'auth_session_test.dart'
    show TestAdapter, jsonResponse, profile, schedules;
import 'attendance_test.dart'
    show FakeRepository, FakeCapture, snapshot, policyJson, recordJson;
import 'package:fpdart/fpdart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio client;
  late AuthService auth;
  var company = 'alpha';
  var denied = false, suspended = false;
  final requests = <RequestOptions>[];
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    company = 'alpha';
    denied = suspended = false;
    requests.clear();
    client = Dio(BaseOptions(baseUrl: 'https://api.example.test/api'));
    client.httpClientAdapter = TestAdapter((request) {
      requests.add(request);
      if (request.path == '/auth/login') {
        company = (request.data as Map)['workspace'] as String;
        return jsonResponse({'token': 'opaque-$company'}, 201);
      }
      if (request.path == '/auth/me') {
        if (suspended) return jsonResponse({'message': 'Access revoked'}, 403);
        return jsonResponse({
          ...profile,
          'companyId': company,
          'workspace': company,
          'user': {...profile['user'] as Map, 'companyId': company}
        });
      }
      if (request.path == '/schedules') return jsonResponse(schedules);
      return jsonResponse(
          {'message': 'Outside capture radius'}, denied ? 403 : 200);
    });
    auth = AuthService(client: client)..initialize();
  });
  tearDown(() {
    auth.dispose();
    client.close(force: true);
  });
  Future<AppUser> login(String workspace) async => (await auth.login(
          workspace: workspace,
          email: ' Employee@Example.Test ',
          password: ' secret '))
      .getOrElse((failure) => throw failure);

  test('explicit normalized workspace separates identical employee emails',
      () async {
    final first = await login(' Alpha ');
    final second = await login('beta');
    expect(first.email, second.email);
    expect(first.id, second.id);
    expect(first.companyId, 'alpha');
    expect(second.workspace, 'beta');
    expect(first.sessionIdentity, isNot(second.sessionIdentity));
    expect(requests.first.data, {
      'workspace': 'alpha',
      'email': 'employee@example.test',
      'password': ' secret '
    });
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        'opaque-beta');
  });

  test('company code is required before contacting backend', () async {
    final result = await auth.login(
        workspace: '', email: 'a@example.test', password: 'secret');
    expect(result.isLeft(), true);
    expect(requests, isEmpty);
  });

  test('permission 403 retains session; rejected /me ends access', () async {
    await login('alpha');
    denied = true;
    await expectLater(client.post<void>('/attendance/check-in'),
        throwsA(isA<DioException>()));
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        'opaque-alpha');
    suspended = true;
    await expectLater(
        client.get<void>('/notifications'), throwsA(isA<DioException>()));
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        isNull);
  });

  test('delayed protected bytes from a previous session are discarded',
      () async {
    await login('alpha');
    final gate = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = client.httpClientAdapter;
    client.httpClientAdapter = TestAdapter((request) {
      if (request.path == '/private-photo') {
        started.complete();
        return gate.future;
      }
      return (adapter as TestAdapter).respond(request);
    });
    final pending = client.get<List<int>>('/private-photo',
        options: Options(responseType: ResponseType.bytes));
    final rejected = expectLater(
        pending,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await started.future;
    await login('beta');
    gate.complete(ResponseBody.fromBytes([1, 2, 3], 200));
    await rejected;
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        'opaque-beta');
  });

  test('logout while login is pending cannot persist or publish its token',
      () async {
    final started = Completer<void>();
    final gate = Completer<ResponseBody>();
    client.httpClientAdapter = TestAdapter((request) {
      started.complete();
      return gate.future;
    });
    final pending = auth.login(
        workspace: 'alpha', email: 'employee@example.test', password: 'secret');
    await started.future;
    await auth.logout();
    gate.complete(jsonResponse({'token': 'late-token'}, 201));
    expect((await pending).isLeft(), true);
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        isNull);
  });

  test(
      'schedule permission failure validates only /me without recursive loading',
      () async {
    await login('alpha');
    final adapter = client.httpClientAdapter as TestAdapter;
    var checks = 0;
    client.httpClientAdapter = TestAdapter((request) {
      if (request.path == '/schedules') {
        return jsonResponse({'message': 'Forbidden'}, 403);
      }
      if (request.path == '/auth/me') checks++;
      return adapter.respond(request);
    });
    expect((await auth.getCurrentUser()).isLeft(), true);
    expect(checks, 2);
    expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
        'opaque-alpha');
  });

  test('company-only identity change disposes personal attendance state',
      () async {
    final first = await login('alpha');
    final second = await login('beta');
    final repository = FakeRepository([
      right(snapshot(records: [recordJson()])),
      right(snapshot())
    ]);
    final container = ProviderContainer(overrides: [
      attendanceRepositoryProvider.overrideWithValue(repository),
      attendanceCaptureProvider.overrideWithValue(FakeCapture()),
      sessionProvider.overrideWith(
          (ref) => _Session(repository: AuthRepositoryImpl(service: auth))),
    ]);
    addTearDown(container.dispose);
    (container.read(sessionProvider.notifier) as _Session).setUser(first);
    final subscription = container.listen(attendanceProvider, (_, __) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    final old = container.read(attendanceProvider.notifier);
    expect(container.read(attendanceProvider).snapshot!.records, isNotEmpty);
    (container.read(sessionProvider.notifier) as _Session).setUser(second);
    final current = container.read(attendanceProvider.notifier);
    expect(identical(old, current), false);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(attendanceProvider).snapshot!.records, isEmpty);
  });

  test(
      'branch transfers preserve record snapshots and use current capture policy',
      () {
    final policy = AttendancePolicy.fromJson({
      ...policyJson,
      'branchId': 'new',
      'branchName': 'New branch',
      'latitude': 24.5,
      'longitude': 32.5,
      'radiusMeters': 27,
      'tracking': const {
        'radiusMeters': 230,
        'graceSeconds': 420,
        'updateIntervalSeconds': 30,
        'staleAfterSeconds': 90,
        'maxCaptureAgeSeconds': 60,
        'maxAccuracyMeters': 40,
        'confirmationSeconds': 15
      }
    });
    final result = AttendanceSnapshot.fromJson({
      'workDate': '2026-10-05',
      'schedule': schedules.first,
      'records': [
        {...recordJson(), 'branchId': 'old', 'branchName': 'Saved branch'}
      ]
    }, policy);
    expect(result.current!.branchName, 'Saved branch');
    expect(result.current!.timezone, 'Africa/Cairo');
    expect(result.workDate, '2026-10-05');
    expect(result.policy.branchId, 'new');
    expect(result.policy.latitude, 24.5);
    expect(result.policy.radiusMeters, 27);
    expect(result.policy.tracking!.radiusMeters, 230);
    expect(result.policy.tracking!.graceSeconds, 420);
    expect(result.policy, isNot(AttendancePolicy.fromJson(policyJson)));
  });
}

// Directly controlled session for provider lifecycle verification.
class _Session extends SessionNotifier {
  _Session({required super.repository});
  void setUser(AppUser user) => state = SessionAuthenticated(user);
  @override
  Future<void> restore() async {}
}
