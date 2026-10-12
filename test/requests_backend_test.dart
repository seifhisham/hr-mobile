import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:hrmobile/src/data/models/employee_request.dart';
import 'package:hrmobile/src/utils/failure.dart';
import 'package:hrmobile/src/data/models/attendance_model.dart';
import 'package:hrmobile/src/services/auth_service.dart';
import 'package:hrmobile/src/services/requests_service.dart';
import 'package:hrmobile/src/services/attendance_service.dart';
import 'package:hrmobile/src/services/notifications_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('REQUESTS_TEST_API');
  test(
      'isolated REST request types, allowance, attachments, withdrawal and forgotten departure',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(Uri.parse(base).host, '127.0.0.1',
          reason: 'Throwaway local database only.');
      FlutterSecureStorage.setMockInitialValues({});
      final client = Dio(BaseOptions(baseUrl: base));
      final auth = AuthService(client: client)..initialize();
      addTearDown(() {
        auth.dispose();
        client.close(force: true);
      });
      final user = (await auth.login(
              email: 'mobile-employee@example.test',
              password: 'Isolated-employee-password-2026'))
          .getOrElse((f) => throw f);
      final service = RequestsService(client: client);
      expect((await service.load()).getOrElse((f) => throw f), isEmpty);
      final pdf = RequestAttachment(
          name: 'note.pdf',
          mimeType: 'application/pdf',
          content: base64Encode(utf8.encode('%PDF-1.4\n')));
      final today = DateTime.parse(user.today);
      String date(int day) => DateTime.utc(today.year, today.month, day)
          .toIso8601String()
          .substring(0, 10);
      for (final type in requestTypes
          .where((t) => t != 'excuse' && t != 'forgotten-check-out')) {
        final input = DateRangeRequest(
            type: type,
            from: date(1),
            to: date(1),
            reason: 'Isolated request verification',
            attachments: [pdf]);
        final created = (await service.submit(input)).getOrElse((f) => throw f);
        expect(created.matches(input), true);
        expect(created.status, 'pending');
        expect(created.salaryDeductionDays, isNull);
        expect(created.attachments.single.decode(), pdf.decode());
        expect((await service.submit(input)).isLeft(), true,
            reason: 'Overlap rejected');
        final withdrawn = (await service.withdraw(
                created.id, 'No longer needed for this test'))
            .getOrElse((f) => throw f);
        expect(withdrawn.status, 'withdrawn');
        expect(withdrawn.lastChange!.action, 'withdraw');
        expect(
            (await service.withdraw(
                    created.id, 'Already withdrawn test request'))
                .isLeft(),
            true);
      }
      final excuses = <EmployeeRequest>[];
      for (var day = 1; day <= 3; day++) {
        final input = ExcuseRequest(
            from: date(day),
            to: date(day),
            durationMinutes: 80,
            excuseType: excuseTypes[day - 1],
            shiftId: user.schedule!.id);
        final created = (await service.submit(input)).getOrElse((f) => throw f);
        expect(created.matches(input), true);
        expect(created.reason, '');
        excuses.add(created);
      }
      final excess = ExcuseRequest(
          from: date(4),
          to: date(4),
          durationMinutes: 1,
          excuseType: 'during-shift',
          shiftId: user.schedule!.id);
      expect((await service.submit(excess)).isLeft(), true,
          reason: 'Exactly 240 minutes / 3 requests reserve the allowance');
      await service.withdraw(excuses.first.id, 'Release allowance for test');
      expect((await service.submit(excess)).isRight(), true,
          reason: 'Withdrawal releases monthly allowance');
      final attendanceService = AttendanceService(client: client);
      final initial =
          (await attendanceService.load()).getOrElse((f) => throw f);
      final record = (await attendanceService.submit(AttendanceCapture(
              latitude: initial.policy.latitude,
              longitude: initial.policy.longitude,
              accuracyMeters: 5,
              capturedAt: DateTime.now().toUtc(),
              photo: image.encodeJpg(image.Image(width: 10, height: 10)))))
          .getOrElse((f) => throw f);
      final departure = ForgottenCheckOutRequest(
          attendanceId: record.id,
          proposedCheckOut: DateTime.fromMillisecondsSinceEpoch(
              DateTime.now().millisecondsSinceEpoch,
              isUtc: true),
          reason: 'Forgot departure during isolated test');
      final correction =
          (await service.submit(departure)).getOrElse((f) => throw f);
      expect(correction.attendance!.id, record.id);
      expect(correction.matches(departure), true);
      expect(
          (await attendanceService.load())
              .getOrElse((f) => throw f)
              .records
              .single
              .checkOut,
          isNull);
      expect((await service.submit(departure)).isLeft(), true);
      await service.withdraw(
          correction.id, 'Cancel isolated correction request');
      expect((await service.load()).getOrElse((f) => throw f).length, 11);
      for (final item in (await service.load())
          .getOrElse((f) => throw f)
          .where((r) => r.type == 'excuse' && r.status == 'pending')) {
        await service.withdraw(
            item.id, 'Release reservations for cross-month verification');
      }
      final monthEnd = DateTime.utc(today.year, today.month + 1, 0);
      final nextStart = DateTime.utc(today.year, today.month + 1, 1);
      String calendar(DateTime value) =>
          value.toIso8601String().substring(0, 10);
      final cross = (await service.submit(ExcuseRequest(
              from: calendar(monthEnd),
              to: calendar(nextStart.add(const Duration(days: 1))),
              durationMinutes: 60,
              excuseType: 'during-shift',
              shiftId: user.schedule!.id)))
          .getOrElse((f) => throw f);
      ExcuseRequest next(int days, int minutes) => ExcuseRequest(
          from: calendar(nextStart.add(Duration(days: days))),
          to: calendar(nextStart.add(Duration(days: days))),
          durationMinutes: minutes,
          excuseType: 'during-shift',
          shiftId: user.schedule!.id);
      expect((await service.submit(next(2, 121))).isLeft(), true);
      expect((await service.submit(next(2, 120))).isRight(), true);
      expect((await service.submit(next(3, 1))).isLeft(), true);
      await service.withdraw(cross.id, 'Release cross-month reservation');
      expect((await service.submit(next(3, 120))).isRight(), true);

      // HR/dashboard endpoints are used only in this isolated acceptance test.
      final admin = Dio(BaseOptions(baseUrl: base));
      addTearDown(() => admin.close(force: true));
      final adminSession = await admin.post<Map<String, dynamic>>('/auth/login',
          data: {
            'email': 'admin@example.test',
            'password': 'Isolated-admin-password-2026'
          });
      admin.options.headers['Authorization'] =
          'Bearer ${adminSession.data!['token']}';
      final mission = (await service.submit(DateRangeRequest(
              type: 'mission',
              from: date(10),
              to: date(10),
              reason: 'Isolated approval verification')))
          .getOrElse((f) => throw f);
      final approved = await admin.patch<Map<String, dynamic>>(
          '/requests/${mission.id}/decision',
          data: {
            'status': 'approved',
            'reason': 'Approved isolated test request'
          });
      expect(EmployeeRequest.fromJson(approved.data!).salaryDeductionDays, 1);
      final notifications = NotificationsService(client: client);
      final inbox = (await notifications.load()).getOrElse((f) => throw f);
      final alert = inbox.items.singleWhere((n) => n.requestId == mission.id);
      expect(alert.type, 'request-decided');
      expect(alert.unread, true);
      final read =
          (await notifications.markRead(alert.id)).getOrElse((f) => throw f);
      final repeated =
          (await notifications.markRead(alert.id)).getOrElse((f) => throw f);
      expect(repeated.readAt, read.readAt);
      expect((await service.loadManaged()).getOrElse((f) => throw f), isEmpty);
      await auth.logout();
      (await auth.login(
              email: 'mobile-employee@example.test',
              password: 'Isolated-employee-password-2026'))
          .getOrElse((f) => throw f);
      final restoredInbox =
          (await notifications.load()).getOrElse((f) => throw f);
      expect(restoredInbox.items.singleWhere((n) => n.id == alert.id).readAt,
          read.readAt);
      expect(restoredInbox.unreadCount, inbox.unreadCount - 1);
      expect(
          (await service.withdraw(mission.id, 'Cannot withdraw final decision'))
              .isLeft(),
          true);
      await admin.patch<Map<String, dynamic>>('/requests/${mission.id}/reopen',
          data: {'reason': 'Reopen isolated test request'});
      final reopened = (await service.load())
          .getOrElse((f) => throw f)
          .singleWhere((r) => r.id == mission.id);
      expect(reopened.status, 'pending');
      expect(reopened.lastChange!.action, 'reopen');
      expect(reopened.salaryDeductionDays, isNull);
      final reopenedInbox =
          (await notifications.load()).getOrElse((f) => throw f);
      expect(
          reopenedInbox.items.any((n) =>
              n.requestId == mission.id &&
              n.type == 'request-reopened' &&
              n.unread),
          true);
      await service.withdraw(mission.id, 'Withdraw reopened request');
      final sick = (await service.submit(DateRangeRequest(
              type: 'sick',
              from: date(11),
              to: date(11),
              reason: 'Isolated rejection verification')))
          .getOrElse((f) => throw f);
      final rejected = await admin
          .patch<Map<String, dynamic>>('/requests/${sick.id}/decision', data: {
        'status': 'rejected',
        'reason': 'Rejected isolated test request'
      });
      expect(EmployeeRequest.fromJson(rejected.data!).salaryDeductionDays, 3);
      final replacement =
          (await service.submit(departure)).getOrElse((f) => throw f);
      await admin.patch<Map<String, dynamic>>(
          '/requests/${replacement.id}/decision',
          data: {
            'status': 'approved',
            'reason': 'Confirmed isolated departure'
          });
      // AC-15–16: real authorization, recommendations and changed assignments.
      final managerClient = Dio(BaseOptions(baseUrl: base));
      final managerAuth = AuthService(client: managerClient)..initialize();
      addTearDown(() {
        managerAuth.dispose();
        managerClient.close(force: true);
      });
      final manager = (await managerAuth.login(
              email: 'mobile-manager@example.test',
              password: 'Isolated-manager-password-2026'))
          .getOrElse((f) => throw f);
      final managerService = RequestsService(client: managerClient);
      await admin.patch<Map<String, dynamic>>(
          '/departments/Engineering/manager',
          data: {'employeeId': manager.employee!.id});
      for (final status in ['approved', 'rejected']) {
        final day = status == 'approved' ? 20 : 21;
        final request = (await service.submit(DateRangeRequest(
                type: 'mission',
                from: date(day),
                to: date(day),
                reason: 'Manager recommendation test')))
            .getOrElse((f) => throw f);
        expect(
            (await managerService.loadManaged())
                .getOrElse((f) => throw f)
                .any((r) => r.id == request.id),
            true);
        expect(
            (await service.review(
                    request.id, status, 'Cannot review own request'))
                .fold((f) => (f as ServerFailure).statusCode, (_) => null),
            403);
        expect(
            (await managerService.review(request.id, status, 'bad')).isLeft(),
            true);
        final reviewed = (await managerService.review(
                request.id, status, '  Coverage recommendation  '))
            .getOrElse((f) => throw f);
        expect(reviewed.status, 'pending');
        expect(reviewed.managerStage, status);
        expect(reviewed.managerReview!.reason, 'Coverage recommendation');
        expect(reviewed.managerReview!.employeeId, manager.employee!.id);
        expect(reviewed.salaryDeductionDays, isNull);
        expect(
            (await managerService.review(
                    request.id, status, 'Repeated recommendation'))
                .fold((f) => (f as ServerFailure).statusCode, (_) => null),
            409);
        expect(
            (await notifications.load()).getOrElse((f) => throw f).items.any(
                (n) =>
                    n.requestId == request.id && n.type == 'manager-reviewed'),
            true);
      }
      final own = (await managerService.submit(DateRangeRequest(
              type: 'mission',
              from: date(22),
              to: date(22),
              reason: 'Manager own request')))
          .getOrElse((f) => throw f);
      expect(
          (await managerService.loadManaged())
              .getOrElse((f) => throw f)
              .any((r) => r.id == own.id),
          false);
      expect(
          (await managerService.review(
                  own.id, 'approved', 'Cannot review self'))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          403);
      final stale = (await service.submit(DateRangeRequest(
              type: 'mission',
              from: date(23),
              to: date(23),
              reason: 'Assignment change test')))
          .getOrElse((f) => throw f);
      await admin.patch<Map<String, dynamic>>(
          '/departments/Engineering/manager',
          data: {'employeeId': null});
      expect(
          (await managerService.review(
                  stale.id, 'approved', 'Former manager recommendation'))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          403);
      expect((await managerService.loadManaged()).getOrElse((f) => throw f),
          isEmpty);
      final closed = (await attendanceService.load())
          .getOrElse((f) => throw f)
          .records
          .single;
      expect(closed.id, record.id);
      expect(closed.checkOut, departure.proposedCheckOut);
      expect(
          (await attendanceService.loadEvidence(record.id))
              .getOrElse((f) => throw f)
              .length,
          1,
          reason: 'Correction does not fabricate check-out evidence');
    }, _RealHttpOverrides());
  },
      skip: base.isEmpty
          ? 'Requires isolated request backend; see README.md.'
          : false);
}
