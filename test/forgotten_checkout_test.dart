import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/data/models/employee_request.dart';
import 'package:hodour/src/services/attendance_service.dart';
import 'package:hodour/src/ui/attendance/attendance_provider.dart';
import 'package:hodour/src/ui/requests/requests_provider.dart';
import 'attendance_test.dart';
import 'attendance_location_test.dart'
    show LocationSource, LocationApi, monitored;
import 'package:hodour/src/ui/attendance/attendance_monitor_provider.dart';
import 'auth_session_test.dart' show TestAdapter, jsonResponse, schedules;
import 'requests_test.dart' show requestJson, FakeRequests;

Map<String, dynamic> forgotten(String attendanceId,
        {String status = 'pending', String type = 'forgotten-check-out'}) =>
    {
      ...requestJson(status: status),
      'type': type,
      'attendanceId': attendanceId,
      'managerStage': 'rejected'
    };
AttendanceSnapshot workday(List<Map<String, dynamic>> records,
        List<Map<String, dynamic>> requests) =>
    AttendanceSnapshot.fromJson({
      'workDate': '2026-10-05',
      'records': records,
      'schedule': schedules.first
    }, AttendancePolicy.fromJson(policyJson),
        requests: requests.map(EmployeeRequest.fromJson).toList());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final older = recordJson(date: '2026-10-04');
  test('pending overall status unlocks without closing attendance', () {
    final data = workday([older], [forgotten('owned-record')]);
    expect(data.canSubmit, isTrue);
    expect(data.awaitingForgottenApproval, isTrue);
    expect(data.records.single.checkOut, isNull);
    expect(data.open, isNull);
  });
  test('unmatched, wrong type, rejected and withdrawn requests block', () {
    for (final request in [
      forgotten('other'),
      forgotten('owned-record', type: 'leave'),
      forgotten('owned-record', status: 'rejected'),
      forgotten('owned-record', status: 'withdrawn'),
      forgotten('owned-record', status: 'approved')
    ]) {
      expect(workday([older], [request]).canSubmit, isFalse);
    }
    expect(workday([older], []).canSubmit, isFalse);
  });
  test('every earlier open record needs its own pending request', () {
    final records = [
      older,
      {...older, 'id': 'second', 'workDate': '2026-10-03'}
    ];
    expect(workday(records, [forgotten('owned-record')]).canSubmit, isFalse);
    expect(
        workday(records, [forgotten('owned-record'), forgotten('second')])
            .canSubmit,
        isTrue);
  });
  test(
      'checkout and tracking target current server workday despite older records',
      () async {
    final data = workday([
      older,
      {...recordJson(), 'id': 'today'}
    ], []);
    expect(data.canSubmit, isTrue);
    expect(data.open?.id, 'today');
    final repository = FakeRepository([right(data), right(data), right(data)])
      ..result = right(AttendanceRecord.fromJson(
          {...recordJson(closed: true), 'id': 'today'}));
    final controller =
        AttendanceController(repository, FakeCapture(), enabled: false);
    await controller.refresh();
    await controller.submit();
    expect(repository.checkOutId, 'today');
    controller.dispose();
    final source = LocationSource();
    final api = LocationApi();
    final monitor = AttendanceMonitor(source, api, reconcile: () async {});
    final tracking = monitored(id: 'today');
    monitor.sync(AttendanceSnapshot(
        workDate: data.workDate,
        records: data.records,
        schedule: data.schedule,
        policy: tracking.policy));
    expect(monitor.state.record?.id, 'today');
    source.access.complete();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls.single.id, 'today');
    monitor.dispose();
    await source.stream.close();
    expect(workday([older, recordJson(closed: true)], []).canSubmit, isFalse);
  });
  test('refresh follows pagination and reflects final HR approval', () async {
    var approved = false;
    final cursors = <Object?>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.httpClientAdapter = TestAdapter((options) {
      if (options.path == '/attendance/policy') return jsonResponse(policyJson);
      if (options.path == '/attendance/me') {
        return jsonResponse({
          'workDate': '2026-10-05',
          'schedule': schedules.first,
          'records': [recordJson(date: '2026-10-04', closed: approved)]
        });
      }
      cursors.add(options.queryParameters['before']);
      expect(options.queryParameters['limit'], 50);
      if (options.queryParameters['before'] == null) {
        return jsonResponse(
            [for (var i = 0; i < 50; i++) requestJson(id: 'request-$i')]);
      }
      return jsonResponse([
        forgotten('owned-record', status: approved ? 'approved' : 'pending')
      ]);
    });
    final controller = AttendanceController(
        AttendanceService(client: dio), FakeCapture(),
        enabled: false);
    await controller.refresh();
    expect(controller.state.snapshot!.canSubmit, isTrue);
    expect(controller.state.snapshot!.records.single.checkOut, isNull);
    approved = true;
    await controller.refresh();
    expect(controller.state.snapshot!.records.single.checkOut, isNotNull);
    expect(controller.state.snapshot!.awaitingForgottenApproval, isFalse);
    expect(cursors, [null, 'request-49', null, 'request-49']);
    controller.dispose();
    dio.close();
  });
  test('request changes during an attendance refresh force a fresh read',
      () async {
    final repository = FakeRepository([
      right(workday([older], [])),
      right(workday([older], [forgotten('owned-record')]))
    ])
      ..loadWait = Completer<void>();
    final controller =
        AttendanceController(repository, FakeCapture(), enabled: false);
    final loading = controller.refresh();
    final changed = controller.refresh(afterMutation: true);
    repository.loadWait!.complete();
    await Future.wait([loading, changed]);
    expect(repository.responses, isEmpty);
    expect(controller.state.snapshot!.canSubmit, isTrue);
    controller.dispose();
  });
  test('refreshing request history after HR approval refreshes attendance',
      () async {
    final pending = EmployeeRequest.fromJson(forgotten('owned-record'));
    final approved =
        EmployeeRequest.fromJson(forgotten('owned-record', status: 'approved'));
    final repository = FakeRequests([
      right([pending]),
      right([approved])
    ]);
    var refreshes = 0;
    final controller =
        RequestsController(repository, enabled: false, onChanged: () async {
      refreshes++;
    });
    await controller.refresh();
    expect(refreshes, 0);
    await controller.refresh();
    expect(refreshes, 1);
    controller.dispose();
  });
  test(
      'request submission and withdrawal refresh attendance after own requests',
      () async {
    final input = ForgottenCheckOutRequest(
        attendanceId: 'owned-record',
        proposedCheckOut: DateTime.parse('2026-10-04T15:00:00Z'),
        reason: 'Forgot departure');
    final pending = EmployeeRequest.fromJson(forgotten('owned-record'));
    final withdrawn = EmployeeRequest.fromJson(
        forgotten('owned-record', status: 'withdrawn'));
    final repository = FakeRequests([
      right([]),
      right([pending]),
      right([withdrawn])
    ], response: right(pending));
    var refreshes = 0;
    final controller =
        RequestsController(repository, enabled: false, onChanged: () async {
      refreshes++;
    });
    await controller.refresh();
    await controller.submit(input);
    expect(refreshes, 1);
    repository.response = right(withdrawn);
    await controller.withdraw(pending, 'No longer needed');
    expect(refreshes, 2);
    controller.dispose();
  });
}
