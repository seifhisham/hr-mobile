import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:hrmobile/src/data/models/employee_request.dart';
import 'package:hrmobile/src/data/models/user_model.dart';
import 'package:hrmobile/src/data/models/attendance_model.dart';
import 'package:hrmobile/src/data/repositories/requests_repository.dart';
import 'package:hrmobile/src/services/requests_service.dart';
import 'package:hrmobile/src/ui/requests/requests_provider.dart';
import 'package:hrmobile/src/utils/utils.dart';
import 'auth_session_test.dart'
    show TestAdapter, jsonResponse, profile, schedules;
import 'attendance_test.dart' show recordJson;

Map<String, dynamic> requestJson(
        {String id = 'request-a',
        String status = 'pending',
        RequestSubmission? input}) =>
    {
      ...input?.toJson() ??
          const {
            'type': 'leave',
            'from': '2026-10-05',
            'to': '2026-10-05',
            'reason': 'Personal appointment'
          },
      'id': id,
      'employeeId': 'employee-a',
      'employeeName': 'Test Employee',
      'nationalId': '00123456789012',
      'status': status,
      'submittedAt': '2026-10-06T10:00:00Z',
      'decidedAt': null,
      'decidedBy': null,
      'decisionReason': null,
      'salaryDeductionDays': null,
      'attendance': null,
    };
const submission = DateRangeRequest(
    type: 'leave',
    from: '2026-10-05',
    to: '2026-10-05',
    reason: 'Personal appointment');

class FakeRequests implements RequestsRepository {
  @override
  FutureEither<List<EmployeeRequest>> loadManaged() => load();
  FakeRequests(this.loads, {this.response});
  final List<Either<Failure, List<EmployeeRequest>>> loads;
  Either<Failure, EmployeeRequest>? response;
  Completer<void>? wait;
  Completer<void>? loadWait;
  int posts = 0, patches = 0;
  @override
  FutureEither<List<EmployeeRequest>> load() async {
    await loadWait?.future;
    return loads.removeAt(0);
  }

  @override
  FutureEither<EmployeeRequest> submit(RequestSubmission input) async {
    posts++;
    await wait?.future;
    return response ?? left(const NetworkFailure('Lost response'));
  }

  @override
  FutureEither<EmployeeRequest> review(
      String id, String status, String reason) async {
    patches++;
    await wait?.future;
    return response ?? left(const NetworkFailure('Lost response'));
  }

  @override
  FutureEither<EmployeeRequest> withdraw(String id, String reason) async {
    patches++;
    return response ?? left(const NetworkFailure('Lost response'));
  }
}

void main() {
  EmployeeRequest managedItem(
          {String stage = 'pending', String reason = 'Coverage arranged'}) =>
      EmployeeRequest.fromJson({
        ...requestJson(),
        'employeeId': 'colleague',
        'managerEmployeeId': 'manager',
        'managerStage': stage,
        if (stage != 'pending')
          'managerReview': {
            'status': stage,
            'employeeId': 'manager',
            'reviewedBy': 'Manager',
            'reviewedAt': '2026-10-07T10:00:00Z',
            'reason': reason
          }
      });
  test(
      'manager review validates authorization and reason, blocks duplicates and reconciles lost response',
      () async {
    final item = managedItem();
    final reviewed = managedItem(stage: 'approved');
    final repository = FakeRequests([
      right([item]),
      right([reviewed])
    ]);
    final controller = RequestsController(repository,
        enabled: false, managed: true, employeeId: 'manager');
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.review(item, 'approved', 'bad');
    await controller.review(item, 'withdrawn', 'Coverage arranged');
    expect(repository.patches, 0);
    repository.wait = Completer<void>();
    final action = controller.review(item, 'approved', '  Coverage arranged  ');
    await controller.review(item, 'rejected', 'Coverage unavailable');
    expect(repository.patches, 1);
    repository.wait!.complete();
    await action;
    expect(controller.state.pending, isNull);
    expect(controller.state.noticeKey, 'requests.confirmed');
    expect(controller.state.items.single.status, 'pending');
    expect(controller.state.items.single.salaryDeductionDays, isNull);
    await controller.review(item, 'approved', 'Coverage arranged');
    expect(repository.patches, 1);
    expect(item.canReview('colleague'), false);
    expect(item.canReview('wrong-manager'), false);
    expect(item.canReview(null), false);
  });
  test(
      'failed manager reconciliation blocks reviews until refreshed; 403 removes stale access',
      () async {
    final item = managedItem();
    final repository = FakeRequests([
      right([item]),
      left(const NetworkFailure('Offline')),
      right([item]),
      right([])
    ]);
    final controller = RequestsController(repository,
        enabled: false, managed: true, employeeId: 'manager');
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.review(item, 'rejected', 'Coverage unavailable');
    expect(controller.state.pending, isA<PendingManagerReview>());
    await controller.review(item, 'rejected', 'Coverage unavailable');
    expect(repository.patches, 1);
    await controller.refresh();
    expect(controller.state.pending, isNull);
    expect(controller.state.noticeKey, 'requests.not_confirmed');
    repository.response =
        left(const ServerFailure('Assignment changed', statusCode: 403));
    await controller.review(item, 'rejected', 'Coverage unavailable');
    expect(controller.state.items, isEmpty);
    expect(controller.state.action, isA<RequestFailure<EmployeeRequest>>());
  });
  test(
      'review service sends strict trimmed payload and preserves server workflow',
      () async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    addTearDown(() => client.close());
    client.httpClientAdapter = TestAdapter((request) {
      expect(request.method, 'PATCH');
      expect(request.path, '/requests/request-a/manager-review');
      expect(request.data,
          {'status': 'rejected', 'reason': 'Coverage unavailable'});
      return jsonResponse({...requestJson(), 'managerStage': 'rejected'});
    });
    final result = (await RequestsService(client: client)
            .review('request-a', 'rejected', ' Coverage unavailable '))
        .getOrElse((f) => throw f);
    expect(result.status, 'pending');
    expect(result.managerStage, 'rejected');
    expect(result.salaryDeductionDays, isNull);
  });
  test('managed queue follows cursor pages from the first page', () async {
    final calls = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    addTearDown(() => client.close());
    client.httpClientAdapter = TestAdapter((request) {
      calls.add(request);
      expect(request.path, '/requests/managed');
      expect(request.queryParameters['limit'], 50);
      return jsonResponse(request.queryParameters['before'] == null
          ? List.generate(50, (i) => requestJson(id: 'request-$i'))
          : [requestJson(id: 'notification-target')]);
    });
    final service = RequestsService(client: client);
    final items = (await service.loadManaged()).getOrElse((f) => throw f);
    expect(items.last.id, 'notification-target');
    expect(items.length, 51);
    expect(calls[1].queryParameters['before'], 'request-49');
    await service.loadManaged();
    expect(calls[2].queryParameters.containsKey('before'), false);
  });
  for (final code in [403, 404, 409]) {
    test('manager review $code blocks actions even if refresh fails', () async {
      final item = managedItem();
      final repository = FakeRequests([
        right([item]),
        left(const NetworkFailure('Offline'))
      ], response: left(ServerFailure('Review unavailable', statusCode: code)));
      final controller = RequestsController(repository,
          enabled: false, managed: true, employeeId: 'manager');
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.review(item, 'approved', 'Coverage arranged');
      expect(controller.state.noticeKey, 'requests.review_unavailable');
      await controller.review(item, 'rejected', 'Coverage unavailable');
      expect(repository.patches, 1);
    });
  }
  final user = AppUser.fromJson(profile,
      schedule: WorkSchedule.fromJson(schedules.first));
  test(
      'all request types serialize exact allowed fields and preserve calendar dates',
      () {
    for (final type in requestTypes
        .where((t) => t != 'excuse' && t != 'forgotten-check-out')) {
      final request = DateRangeRequest(
          type: type,
          from: '2026-10-05',
          to: '2026-10-06',
          reason: '  Personal appointment  ');
      expect(request.toJson().keys.toSet(), {'type', 'from', 'to', 'reason'});
      expect(request.validate(user), isNull);
      expect(
          EmployeeRequest.fromJson(requestJson(input: request))
              .matches(request),
          isTrue);
    }
    final excuse = ExcuseRequest(
        from: '2026-10-05',
        to: '2026-10-05',
        durationMinutes: 15,
        excuseType: 'arriving-late',
        shiftId: user.schedule!.id);
    expect(excuse.validate(user), isNull);
    expect(excuse.toJson().keys.toSet(), {
      'type',
      'from',
      'to',
      'durationMinutes',
      'excuseType',
      'shiftId',
      'reason'
    });
    final attendance = AttendanceRecord.fromJson(recordJson());
    final forgotten = ForgottenCheckOutRequest(
        attendanceId: attendance.id,
        proposedCheckOut: attendance.checkIn.add(const Duration(hours: 1)),
        reason: 'Forgot departure');
    expect(forgotten.toJson().keys.toSet(),
        {'type', 'attendanceId', 'proposedCheckOut', 'reason'});
    expect(
        forgotten.validate(user,
            attendance: attendance, now: DateTime.utc(2026, 10, 7)),
        isNull);
    expect(
        forgotten.validate(user,
            attendance: AttendanceRecord.fromJson(recordJson(closed: true))),
        'requests.open_record_required');
  });
  test(
      'inclusive 93-day range, invalid calendar dates, employment and shift limits',
      () {
    expect(validateRange('2026-10-01', '2027-01-01', user.employee!.startDate),
        isNull);
    expect(validateRange('2026-10-01', '2027-01-02', user.employee!.startDate),
        'requests.range_invalid');
    expect(validateRange('2026-02-30', '2026-03-01', '2026-01-01'),
        'requests.range_invalid');
    expect(validateRange('2026-09-30', '2026-10-01', user.employee!.startDate),
        'requests.before_employment');
    expect(shiftMinutes(user.schedule!), 480);
    final excuse = ExcuseRequest(
        from: '2026-10-05',
        to: '2026-10-05',
        durationMinutes: 481,
        excuseType: 'during-shift',
        shiftId: user.schedule!.id);
    expect(excuse.validate(user), 'requests.duration_invalid');
  });
  test('Cairo local departure detects nonexistent and repeated clock times',
      () {
    tzdata.initializeTimeZones();
    expect(departureInstants(DateTime(2026, 4, 24), 0, 30, 'Africa/Cairo'),
        isEmpty);
    final repeated =
        departureInstants(DateTime(2026, 10, 29), 23, 30, 'Africa/Cairo');
    expect(repeated.length, 2);
    expect(repeated[1].difference(repeated[0]), const Duration(hours: 1));
    expect(
        departureInstants(DateTime(2026, 10, 6), 12, 0, 'Africa/Cairo').single,
        DateTime.utc(2026, 10, 6, 9));
  });
  test('attachment count, size, MIME and safe base64 decoding', () {
    final file = RequestAttachment(
        name: 'note.pdf',
        mimeType: 'application/pdf',
        content: base64Encode(utf8.encode('%PDF-1.4\n')));
    expect(file.decode(), isNotEmpty);
    expect(validateAttachments([file, file, file, file]),
        'requests.attachment_limit');
    expect(
        () => const RequestAttachment(
                name: 'note.pdf', mimeType: 'application/pdf', content: '!!!!')
            .decode(),
        throwsFormatException);
    final bytes = List<int>.filled(RequestAttachment.maxBytes, 65)
      ..setRange(0, 5, ascii.encode('%PDF-'));
    expect(
        RequestAttachment(
                name: 'large.pdf',
                mimeType: 'application/pdf',
                content: base64Encode(bytes))
            .decode()
            .length,
        RequestAttachment.maxBytes);
    expect(
        () => RequestAttachment(
            name: 'note.pdf',
            mimeType: 'application/pdf',
            content: base64Encode([...bytes, 65])).decode(),
        throwsFormatException);
    expect(
        () => RequestAttachment(
                name: 'photo.jpg',
                mimeType: 'image/jpeg',
                content: file.content)
            .decode(),
        throwsFormatException);
  });
  test(
      'models preserve nullable historical fields and separate manager recommendation',
      () {
    final historical = EmployeeRequest.fromJson(requestJson());
    expect(historical.managerStage, isNull);
    expect(historical.salaryDeductionDays, isNull);
    final reviewed = EmployeeRequest.fromJson({
      ...requestJson(),
      'managerStage': 'rejected',
      'managerReview': const {
        'status': 'rejected',
        'reviewedBy': 'Department manager',
        'reviewedAt': '2026-10-06T10:01:00Z',
        'reason': 'No department coverage'
      }
    });
    expect(reviewed.status, 'pending');
    expect(reviewed.canWithdraw, isTrue);
    expect(reviewed.managerReview!.status, 'rejected');
    expect(filterRequests([historical, reviewed], status: 'approved'), isEmpty);
    expect(
        EmployeeRequest.fromJson(requestJson(status: 'approved')).canWithdraw,
        isFalse);
  });
  test('REST uses own endpoints, JSON bodies and withdrawal reason only',
      () async {
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    client.httpClientAdapter = TestAdapter((request) {
      if (request.method == 'GET') {
        expect(request.path, '/requests/me');
        return jsonResponse([requestJson()]);
      }
      if (request.method == 'POST') {
        expect(request.path, '/requests');
        expect(request.data, submission.toJson());
        return jsonResponse(requestJson(), 201);
      }
      expect(request.path, '/requests/request-a/withdraw');
      expect(request.data, {'reason': 'No longer needed'});
      return jsonResponse(requestJson(status: 'withdrawn'));
    });
    final service = RequestsService(client: client);
    expect((await service.load()).isRight(), true);
    expect((await service.submit(submission)).isRight(), true);
    expect(
        (await service.withdraw('request-a', '  No longer needed  ')).isRight(),
        true);
  });
  test('lost creation is reconciled against new IDs without a duplicate POST',
      () async {
    final item = EmployeeRequest.fromJson(requestJson());
    final fake = FakeRequests([
      right([]),
      right([item])
    ]);
    final controller = RequestsController(fake, enabled: false);
    await controller.refresh();
    await controller.submit(submission);
    expect(fake.posts, 1);
    expect(controller.state.action, isA<RequestSuccess<EmployeeRequest>>());
    expect(controller.state.noticeKey, 'requests.confirmed');
    expect(controller.state.pending, isNull);
    controller.dispose();
  });
  test(
      'failed reconciliation blocks resubmission; an old matching item is not a new success',
      () async {
    final old = EmployeeRequest.fromJson(requestJson());
    final fake = FakeRequests([
      right([old]),
      left(const NetworkFailure('Offline')),
      right([old])
    ]);
    final controller = RequestsController(fake, enabled: false);
    await controller.refresh();
    await controller.submit(submission);
    await controller.submit(submission);
    expect(fake.posts, 1);
    expect(controller.state.pending, isNotNull);
    await controller.refresh();
    expect(controller.state.noticeKey, 'requests.not_confirmed');
    expect(controller.state.action, isA<RequestFailure<EmployeeRequest>>());
    controller.dispose();
  });
  test('unknown withdrawal refreshes final state and never repeats PATCH',
      () async {
    final item = EmployeeRequest.fromJson(requestJson());
    final withdrawn =
        EmployeeRequest.fromJson(requestJson(status: 'withdrawn'));
    final fake = FakeRequests([
      right([item]),
      right([withdrawn])
    ]);
    final controller = RequestsController(fake, enabled: false);
    await controller.refresh();
    await controller.withdraw(item, 'No longer needed');
    expect(fake.patches, 1);
    expect(controller.state.items.single.status, 'withdrawn');
    expect(controller.state.noticeKey, 'requests.confirmed');
    controller.dispose();
  });
  test('duplicate taps and disposed account ignore a late creation response',
      () async {
    final fake = FakeRequests([right([])])..wait = Completer<void>();
    final controller = RequestsController(fake, enabled: false);
    await controller.refresh();
    final first = controller.submit(submission);
    await controller.submit(submission);
    expect(fake.posts, 1);
    controller.dispose();
    fake.wait!.complete();
    await first;
    expect(fake.loads, isEmpty);
  });
}
