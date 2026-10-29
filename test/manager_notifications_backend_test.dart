import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/models/employee_request.dart';
import 'package:hodour/src/services/auth_service.dart';
import 'package:hodour/src/services/notifications_service.dart';
import 'package:hodour/src/services/requests_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('REQUESTS_TEST_API');
  test('manager notification approval and rejection remain recommendations',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(Uri.parse(base).host, '127.0.0.1');
      FlutterSecureStorage.setMockInitialValues({});
      final employeeClient = Dio(BaseOptions(baseUrl: base));
      final managerClient = Dio(BaseOptions(baseUrl: base));
      final admin = Dio(BaseOptions(baseUrl: '$base/'));
      final employeeAuth = AuthService(client: employeeClient)..initialize();
      final managerAuth = AuthService(client: managerClient)..initialize();
      addTearDown(() {
        employeeAuth.dispose();
        managerAuth.dispose();
        employeeClient.close(force: true);
        managerClient.close(force: true);
        admin.close(force: true);
      });
      final employee = (await employeeAuth.login(
              workspace: const String.fromEnvironment('TEST_WORKSPACE',
                  defaultValue: 'test-company'),
              email: 'mobile-employee@example.test',
              password: 'Isolated-employee-password-2026'))
          .getOrElse((f) => throw f);
      final manager = (await managerAuth.login(
              workspace: const String.fromEnvironment('TEST_WORKSPACE',
                  defaultValue: 'test-company'),
              email: 'mobile-manager@example.test',
              password: 'Isolated-manager-password-2026'))
          .getOrElse((f) => throw f);
      final session =
          await admin.post<Map<String, dynamic>>('auth/login', data: {
        'workspace': const String.fromEnvironment('TEST_WORKSPACE',
            defaultValue: 'test-company'),
        'email': 'admin@example.test',
        'password': 'Isolated-admin-password-2026'
      });
      admin.options.headers['Authorization'] =
          'Bearer ${session.data!['token']}';
      final profiles = (await admin.get<List<dynamic>>('employees')).data!;
      for (final id in [manager.employee!.id, employee.employee!.id]) {
        final profile = profiles
            .cast<Map<String, dynamic>>()
            .firstWhere((p) => p['id'] == id);
        await admin.patch<Map<String, dynamic>>('employees/$id', data: {
          for (final key in [
            'nationalId',
            'name',
            'email',
            'department',
            'jobTitle',
            'startDate',
            'scheduleId',
            'active'
          ])
            key: profile[key],
          'role': id == manager.employee!.id ? 'manager' : 'employee',
          if (id == employee.employee!.id) 'managerId': manager.employee!.id,
        });
      }
      (await employeeAuth.login(
              workspace: const String.fromEnvironment('TEST_WORKSPACE',
                  defaultValue: 'test-company'),
              email: 'mobile-employee@example.test',
              password: 'Isolated-employee-password-2026'))
          .getOrElse((f) => throw f);
      (await managerAuth.login(
              workspace: const String.fromEnvironment('TEST_WORKSPACE',
                  defaultValue: 'test-company'),
              email: 'mobile-manager@example.test',
              password: 'Isolated-manager-password-2026'))
          .getOrElse((f) => throw f);
      final requests = RequestsService(client: managerClient);
      final notifications = NotificationsService(client: managerClient);
      for (final status in ['approved', 'rejected']) {
        final today = DateTime.parse(employee.today);
        final date = today
            .add(Duration(days: status == 'approved' ? 1 : 2))
            .toIso8601String()
            .substring(0, 10);
        final created = (await RequestsService(client: employeeClient).submit(
                DateRangeRequest(
                    type: 'leave',
                    from: date,
                    to: date,
                    reason: 'Isolated notification test')))
            .getOrElse((f) => throw f);
        final inbox = (await notifications.load()).getOrElse((f) => throw f);
        final alert = inbox.items.firstWhere((n) =>
            n.type == 'manager-review-required' && n.requestId == created.id);
        expect((await notifications.markRead(alert.id)).isRight(), true);
        final current = (await requests.loadManaged())
            .getOrElse((f) => throw f)
            .firstWhere((r) => r.id == alert.requestId);
        expect(current.canReview(manager.employee!.id), true);
        final reviewed = (await requests.review(
                current.id, status, '  Coverage recommendation  '))
            .getOrElse((f) => throw f);
        expect(reviewed.status, 'pending');
        expect(reviewed.managerStage, status);
        expect(reviewed.managerReview!.reason, 'Coverage recommendation');
        expect(reviewed.salaryDeductionDays, isNull);
        expect(
            (await requests.loadManaged())
                .getOrElse((f) => throw f)
                .firstWhere((r) => r.id == created.id)
                .canReview(manager.employee!.id),
            false);
        expect(
            (await notifications.load()).getOrElse((f) => throw f).items.where(
                (n) =>
                    n.requestId == created.id &&
                    n.type == 'manager-review-required'),
            isEmpty);
      }
    }, _RealHttpOverrides());
  }, skip: base.isEmpty);
}
