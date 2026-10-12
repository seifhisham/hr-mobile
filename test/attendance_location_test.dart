import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hrmobile/src/data/models/attendance_location.dart';
import 'package:hrmobile/src/data/models/attendance_model.dart';
import 'package:hrmobile/src/services/attendance_location_source.dart';
import 'package:hrmobile/src/services/attendance_service.dart';
import 'package:hrmobile/src/ui/attendance/attendance_monitor_provider.dart';
import 'package:hrmobile/src/utils/utils.dart';
import 'attendance_test.dart' show policyJson, recordJson;
import 'auth_session_test.dart' show TestAdapter, jsonResponse, schedules;

const trackingJson = {
  'radiusMeters': 150,
  'graceSeconds': 300,
  'updateIntervalSeconds': 30,
  'staleAfterSeconds': 90,
  'maxCaptureAgeSeconds': 60,
  'maxAccuracyMeters': 50,
  'confirmationSeconds': 15,
};
AttendanceSnapshot monitored(
        {bool closed = false,
        String id = 'owned-record',
        String date = '2026-10-05',
        Map<String, dynamic>? location}) =>
    AttendanceSnapshot.fromJson({
      'workDate': '2026-10-05',
      'records': [
        {
          ...recordJson(closed: closed, date: date),
          'id': id,
          'location': location
        }
      ],
      'schedule': schedules.first
    }, AttendancePolicy.fromJson({...policyJson, 'tracking': trackingJson}));
AttendanceLocationFix fix({DateTime? at, double accuracy = 10}) =>
    AttendanceLocationFix(
        latitude: 30.026,
        longitude: 31.528179,
        accuracyMeters: accuracy,
        capturedAt: at ?? DateTime.now().toUtc());

class LocationSource extends AttendanceLocationSource {
  final access = Completer<void>();
  final stream = StreamController<AttendanceLocationFix>.broadcast();
  int captures = 0;
  Failure? failure;
  Completer<AttendanceLocationFix>? captureGate;
  @override
  Future<void> checkAccess() => access.future;
  @override
  Stream<AttendanceLocationFix> positions(AttendanceTrackingPolicy policy) =>
      stream.stream;
  @override
  Future<AttendanceLocationFix> capture() async {
    captures++;
    if (failure != null) throw failure!;
    return captureGate == null ? fix() : captureGate!.future;
  }
}

class LocationApi extends AttendanceService {
  final calls = <({String id, AttendanceLocationFix? fix})>[];
  Either<Failure, AttendanceLocation> result =
      right(const AttendanceLocation(status: 'inside'));
  Completer<void>? gate;
  CancelToken? token;
  @override
  FutureEither<AttendanceLocation> reportLocation(
      String id, AttendanceLocationFix? fix,
      {CancelToken? cancelToken}) async {
    calls.add((id: id, fix: fix));
    token = cancelToken;
    await gate?.future;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocationSource source;
  late LocationApi api;
  late AttendanceMonitor monitor;
  int reconciliations = 0;
  setUp(() {
    source = LocationSource();
    api = LocationApi();
    reconciliations = 0;
    monitor = AttendanceMonitor(source, api, reconcile: () async {
      reconciliations++;
    });
  });
  tearDown(() async {
    if (monitor.mounted) monitor.dispose();
    await source.stream.close();
  });

  test(
      'manual and tracking policy remain separate; all server location fields parse',
      () {
    final snapshot = monitored(location: {
      'status': 'outside',
      'returnBy': '2026-10-12T08:05:00Z',
      'outsideSince': '2026-10-12T07:59:30Z',
      'lastCapturedAt': '2026-10-12T08:00:00Z',
      'distanceMeters': 323.1,
      'accuracyMeters': 10,
      'autoCheckedOutAt': null,
    });
    expect(snapshot.policy.radiusMeters, 50);
    expect(snapshot.policy.tracking!.radiusMeters, 150);
    expect(snapshot.policy.tracking!.graceSeconds, 300);
    expect(snapshot.open!.location!.returnBy, DateTime.utc(2026, 10, 12, 8, 5));
    expect(snapshot.open!.location!.distanceMeters, 323.1);
    expect(
        AttendanceLocation.fromJson(const {'status': 'unavailable'}).returnBy,
        isNull);
    final invalidPolicy = {...trackingJson, 'updateIntervalSeconds': 0};
    expect(() => AttendanceTrackingPolicy.fromJson(invalidPolicy),
        throwsFormatException);
  });

  test(
      'freshness rejects future, stale, repeated and invalid fixes; poor accuracy reaches server',
      () {
    final now = DateTime.now().toUtc();
    final policy = monitored().policy.tracking!;
    expect(fix(at: now).isFresh(now, policy, null), true);
    expect(fix(at: now, accuracy: 100).isFresh(now, policy, null), true);
    expect(fix(at: now).isFresh(now, policy, now), false);
    expect(
        fix(at: now.add(const Duration(seconds: 1))).isFresh(now, policy, null),
        false);
    expect(
        fix(at: now.subtract(const Duration(seconds: 61)))
            .isFresh(now, policy, null),
        false);
    expect(fix(at: now, accuracy: 0).isFresh(now, policy, null), false);
    expect(
        fix(at: now, accuracy: double.nan).isFresh(now, policy, null), false);
  });

  test(
      'REST sends exact JSON, actual capture time and URL-encoded owned ID; accepts 201',
      () async {
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    final payloads = <Object?>[];
    client.httpClientAdapter = TestAdapter((options) {
      expect(options.uri.path, '/api/attendance/owned%2Frecord/location');
      payloads.add(options.data);
      return jsonResponse({'status': 'unavailable'}, 201);
    });
    final service = AttendanceService(client: client);
    final captured = fix(at: DateTime.utc(2026, 10, 12, 8));
    expect((await service.reportLocation('owned/record', captured)).isRight(),
        true);
    expect(payloads.first, {
      'available': true,
      'latitude': 30.026,
      'longitude': 31.528179,
      'accuracyMeters': 10.0,
      'capturedAt': '2026-10-12T08:00:00.000Z'
    });
    await service.reportLocation('owned/record', null);
    expect(payloads.last, {'available': false});
  });

  test('off duty never captures or posts; older open record is the target',
      () async {
    monitor.sync(monitored(closed: true));
    await monitor.report();
    expect(api.calls, isEmpty);
    expect(source.captures, 0);
    monitor.sync(monitored(id: 'older-owned', date: '2026-10-04'));
    await monitor.report(fix: fix());
    expect(api.calls.single.id, 'older-owned');
  });

  test('requests serialize and busy fixes are dropped, not queued', () async {
    monitor.sync(monitored());
    api.gate = Completer<void>();
    final first = monitor.report(fix: fix());
    await monitor.report(fix: fix());
    expect(api.calls.length, 1);
    api.gate!.complete();
    await first;
    expect(api.calls.length, 1);
    expect(reconciliations, 1);
  });
  test(
      'access loss during upload sends unavailability next, without queued coordinates',
      () async {
    monitor.sync(monitored());
    api.gate = Completer<void>();
    final pending = monitor.report(fix: fix());
    await monitor.report(unavailable: true);
    await monitor.report(fix: fix());
    expect(api.calls.length, 1);
    api.gate!.complete();
    await pending;
    expect(api.calls.length, 2);
    expect(api.calls.last.fix, isNull);
    expect(reconciliations, 1);
  });

  test(
      'stale and duplicate fixes send unavailability, never cached coordinates',
      () async {
    monitor.sync(monitored());
    final captured = fix();
    await monitor.report(fix: captured);
    await monitor.report(fix: captured);
    await monitor.report(
        fix: fix(at: DateTime.now().subtract(const Duration(minutes: 2))));
    expect(api.calls.map((call) => call.fix), [captured, null, null]);
    expect(monitor.state.failure, isA<CaptureFailure>());
  });

  test('permission loss sends only unavailability and leaves attendance open',
      () async {
    source.failure = const CaptureFailure('attendance.location_off',
        recovery: CaptureRecovery.locationSettings);
    api.result = right(const AttendanceLocation(status: 'unavailable'));
    monitor.sync(monitored());
    await monitor.report();
    expect(api.calls.single.fix, isNull);
    expect(monitor.state.record!.checkOut, isNull);
    expect(monitor.state.location!.status, 'unavailable');
    expect(monitor.state.failure, source.failure);
  });

  test('network loss reports a connection failure and never closes attendance',
      () async {
    api.result = left(const NetworkFailure('Offline'));
    monitor.sync(monitored());
    await monitor.report(fix: fix());
    expect(monitor.state.failure, isA<NetworkFailure>());
    expect(monitor.state.record!.checkOut, isNull);
    expect(reconciliations, 0);
  });

  test(
      '409 reconciles once without retry; server deadlines and cancellation are authoritative',
      () async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    api.result =
        right(AttendanceLocation(status: 'outside', returnBy: deadline));
    monitor.sync(monitored());
    await monitor.report(fix: fix());
    expect(monitor.state.location!.returnBy, deadline);
    api.result = right(const AttendanceLocation(status: 'inside'));
    await monitor.report(fix: fix());
    expect(monitor.state.location!.returnBy, isNull);
    api.result = left(const ServerFailure('Conflict', statusCode: 409));
    await monitor.report(fix: fix());
    expect(reconciliations, 3);
    expect(api.calls.length, 3);
  });

  test('401 stops and cannot restart from a cached snapshot', () async {
    api.result = left(const ServerFailure('Expired', statusCode: 401));
    monitor.sync(monitored());
    await monitor.report(fix: fix());
    expect(monitor.state.record, isNull);
    monitor.sync(monitored());
    await monitor.report(fix: fix());
    expect(api.calls.length, 1);
  });

  test('confirmed auto checkout stops and closed workday still blocks check-in',
      () async {
    api.result = right(AttendanceLocation(
        status: 'auto-checked-out', autoCheckedOutAt: DateTime.now()));
    monitor.sync(monitored());
    await monitor.report(fix: fix());
    expect(monitor.state.record, isNull);
    expect(reconciliations, 1);
    expect(monitored(closed: true).canSubmit, false);
  });

  test('checkout during acquisition discards late fix without upload',
      () async {
    source.captureGate = Completer<AttendanceLocationFix>();
    monitor.sync(monitored());
    final pending = monitor.report();
    monitor.sync(monitored(closed: true));
    source.captureGate!.complete(fix());
    await pending;
    expect(api.calls, isEmpty);
    expect(monitor.state.record, isNull);
  });

  test(
      'disposed account cancels request and cannot apply its response or reconcile new account',
      () async {
    api.gate = Completer<void>();
    monitor.sync(monitored());
    final pending = monitor.report(fix: fix());
    monitor.dispose();
    expect(api.token!.isCancelled, true);
    api.gate!.complete();
    await pending;
    expect(reconciliations, 0);
  });

  testWidgets(
      'stationary stream still gets a new capture at the policy interval',
      (tester) async {
    monitor.dispose();
    await source.stream.close();
    source = LocationSource();
    api = LocationApi();
    monitor = AttendanceMonitor(source, api, reconcile: () async {});
    source.access.complete();
    monitor.sync(monitored());
    await tester.pump();
    expect(source.captures, 1);
    expect(api.calls.length, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(source.captures, 2);
    expect(api.calls.length, 2);
    monitor.sync(monitored(closed: true));
    await tester.pump(const Duration(minutes: 1));
    expect(source.captures, 2);
    monitor.dispose();
  });
}
