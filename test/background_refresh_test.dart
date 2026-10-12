import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmobile/src/imports/imports.dart';
import 'package:hrmobile/src/data/models/employee_request.dart';
import 'package:hrmobile/src/services/sales_service.dart';
import 'package:hrmobile/src/ui/attendance/attendance_provider.dart';
import 'package:hrmobile/src/ui/requests/requests_provider.dart';
import 'package:hrmobile/src/ui/sales/sales_provider.dart';
import 'attendance_test.dart'
    show FakeCapture, FakeRepository, snapshot, recordJson;
import 'requests_test.dart' show FakeRequests, requestJson;
import 'sales_test.dart' show salesJson, performanceJson;
import 'auth_session_test.dart' show TestAdapter, jsonResponse;

void main() {
  test(
      'attendance tap during a quiet refresh waits and revalidates before capture',
      () async {
    final repository = FakeRepository([
      right(snapshot()),
      right(snapshot()),
      right(snapshot()),
    ]);
    final capture = FakeCapture()..value = null;
    final controller =
        AttendanceController(repository, capture, enabled: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    repository.loadWait = Completer<void>();
    final refresh = controller.refresh();
    final submit = controller.submit();
    expect(capture.calls, 0);
    repository.loadWait!.complete();
    await Future.wait([refresh, submit]);
    expect(capture.calls, 1);
    expect(repository.posts, 0);
    expect(repository.responses, isEmpty);
  });
  test('attendance ignores equal responses and applies changed records',
      () async {
    final repository = FakeRepository([
      right(snapshot(records: [recordJson()])),
      right(snapshot(records: [recordJson()])),
      right(snapshot(records: [recordJson(closed: true)])),
    ]);
    final controller =
        AttendanceController(repository, FakeCapture(), enabled: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    final previous = controller.state;
    repository.loadWait = Completer<void>();
    final refresh = controller.refresh();
    expect(controller.state, same(previous));
    repository.loadWait!.complete();
    await refresh;
    expect(controller.state, same(previous));
    await controller.refresh();
    expect(controller.state.snapshot!.current!.checkOut, isNotNull);
  });

  test(
      'requests stay visible and ignore equal responses, including nested review changes',
      () async {
    final review = {
      'status': 'approved',
      'reviewedBy': 'Manager',
      'reviewedAt': '2026-10-06T10:00:00Z',
      'reason': 'Coverage arranged'
    };
    EmployeeRequest item(String reason) => EmployeeRequest.fromJson({
          ...requestJson(),
          'managerReview': {...review, 'reason': reason}
        });
    final repository = FakeRequests([
      right([item('Coverage arranged')]),
      right([item('Coverage arranged')]),
      right([item('Updated coverage')]),
      left(const NetworkFailure('Offline')),
    ]);
    final controller = RequestsController(repository, enabled: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    final previous = controller.state;
    repository.loadWait = Completer<void>();
    final refresh = controller.refresh();
    expect(controller.state, same(previous));
    repository.loadWait!.complete();
    await refresh;
    expect(controller.state, same(previous));
    await controller.refresh();
    expect(controller.state.items.single.managerReview!.reason,
        'Updated coverage');
    await controller.refresh();
    expect(controller.state.items.single.managerReview!.reason,
        'Updated coverage');
    expect(controller.state.data.isFailure, true);
  });

  test('sales access/dashboard stay visible and only apply changed data',
      () async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    var revision = 3;
    var meetings = 2;
    var canSubmit = true;
    Completer<void>? gate;
    client.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      await gate?.future;
      handler.next(options);
    }));
    client.httpClientAdapter = TestAdapter((options) {
      if (options.path == '/sales/access') {
        return jsonResponse({
          'canSubmit': canSubmit,
          'canReview': true,
          'canSetTargets': false
        });
      }
      if (options.path.contains('performance')) {
        return jsonResponse([
          {...performanceJson(), 'meetings': meetings}
        ]);
      }
      return jsonResponse([salesJson(revision: revision)]);
    });
    final service = SalesService(client: client);
    final access = SalesAccessController(service, enabled: false);
    final list = SalesListController(service,
        month: '2026-10',
        team: false,
        enabled: false,
        onForbidden: access.refresh);
    addTearDown(() {
      access.dispose();
      list.dispose();
      client.close();
    });
    list.setEnabled(true);
    await access.refresh();
    await list.refresh();
    final previousAccess = access.state;
    final previousList = list.state;
    gate = Completer<void>();
    final refreshAccess = access.refresh();
    final refreshList = list.refresh();
    expect(access.state, same(previousAccess));
    expect(list.state, same(previousList));
    gate.complete();
    await Future.wait([refreshAccess, refreshList]);
    expect(access.state, same(previousAccess));
    expect(list.state, same(previousList));
    revision = 4;
    meetings = 3;
    canSubmit = false;
    await Future.wait([access.refresh(), list.refresh()]);
    expect(accessValue(access.state).canSubmit, false);
    expect(list.state.dashboard!.activities.single.revision, 4);
    expect(list.state.dashboard!.performance.single.meetings, 3);
  });
}
