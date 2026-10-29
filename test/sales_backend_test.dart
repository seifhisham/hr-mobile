import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/models/sales_activity.dart';
import 'package:hodour/src/services/sales_service.dart';
import 'package:hodour/src/utils/failure.dart';
import 'package:hodour/src/ui/sales/sales_provider.dart';
import 'package:hodour/src/utils/async_state.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('SALES_TEST_API');
  test(
      'SALES-AC-01–08 isolated mobile REST registration, targets, verification, corrections and permissions',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(Uri.parse(base).host, '127.0.0.1',
          reason: 'Isolated loopback database only.');
      final admin = Dio(BaseOptions(baseUrl: base));
      final token =
          (await admin.post<Map<String, dynamic>>('/auth/login', data: {
        'workspace': const String.fromEnvironment('TEST_WORKSPACE',
            defaultValue: 'test-company'),
        'email': 'admin@example.test',
        'password': 'Isolated-admin-password-2026'
      }))
              .data!['token'];
      admin.options.headers['Authorization'] = 'Bearer $token';
      final schedule =
          (await admin.get<List<dynamic>>('/schedules')).data!.first['id'];
      Future<({Dio client, Map<String, dynamic> employee})> person(
          String name, String department, bool enabled) async {
        final employee =
            (await admin.post<Map<String, dynamic>>('/employees', data: {
          'nationalId': name,
          'name': name,
          'email': '$name@example.test',
          'department': department,
          'jobTitle': 'Isolated fixture',
          'startDate': '2026-01-01',
          'scheduleId': schedule,
          'role': 'employee',
          'active': true,
          'salesEnabled': enabled,
          'password': 'Isolated-sales-password-2026'
        }))
                .data!;
        final client = Dio(BaseOptions(baseUrl: base));
        client.options.headers['Authorization'] =
            'Bearer ${(await client.post<Map<String, dynamic>>('/auth/login', data: {
              'workspace': const String.fromEnvironment('TEST_WORKSPACE',
                  defaultValue: 'test-company'),
              'email': employee['email'],
              'password': 'Isolated-sales-password-2026'
            })).data!['token']}';
        addTearDown(() => client.close(force: true));
        return (client: client, employee: employee);
      }

      final agent = await person('mobile-sales-agent', 'Sales', true);
      final manager = await person('mobile-sales-manager', 'Sales', false);
      final outsider =
          await person('mobile-sales-outsider', 'Operations', true);
      await admin.patch<Map<String, dynamic>>('/departments/Sales/manager',
          data: {'employeeId': manager.employee['id']});
      final me =
          (await agent.client.get<Map<String, dynamic>>('/auth/me')).data!;
      final today = me['today'] as String,
          month = (me['today'] as String).substring(0, 7);
      final own = SalesService(client: agent.client),
          team = SalesService(client: manager.client),
          other = SalesService(client: outsider.client);
      expect((await own.access()).getOrElse((f) => throw f).canSubmit, true);
      expect((await team.access()).getOrElse((f) => throw f).canSubmit, false);
      expect((await team.access()).getOrElse((f) => throw f).canReview, true);
      SalesVisit visit(String kind) => SalesVisit(
          kind: kind,
          activityDate: today,
          clientName: 'Test buyer',
          propertyReference: kind == 'viewing' ? 'Unit A12' : '',
          purpose: 'Discuss property',
          outcome: 'Client interested');
      SalesDeal deal(String type, String reference,
              {String currency = 'EGP'}) =>
          SalesDeal(
              activityDate: today,
              clientName: 'Test buyer',
              propertyReference: 'Unit A12',
              dealReference: reference,
              transactionType: type,
              value: 12000.25,
              currency: currency);
      final entries = <SalesActivity>[];
      for (final input in [
        visit('meeting'),
        visit('viewing'),
        deal('sale', 'Sale-1'),
        deal('lease', 'Lease-1', currency: 'USD')
      ]) {
        final id = newSalesId();
        final created = (await own.create(id, input)).getOrElse((f) => throw f);
        expect(created.id, id);
        expect(created.employeeId, agent.employee['id']);
        expect(created.status, 'pending');
        expect((await own.create(id, input)).getOrElse((f) => throw f).id, id);
        entries.add(created);
      }
      expect(
          (await team.create(newSalesId(), visit('meeting')))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          403);
      var summary =
          (await own.performance(month)).getOrElse((f) => throw f).single;
      expect(summary.meetingTotal, 0);
      expect(summary.deals, 0);
      expect(summary.pending, 4);
      expect(summary.target, isNull);
      expect(summary.achievement['meetings'], isNull);
      await admin.post<Map<String, dynamic>>('/sales/targets', data: {
        'employeeId': agent.employee['id'],
        'month': month,
        'meetings': 1,
        'deals': 2,
        'transactionValue': 24000.5,
        'currency': 'EGP',
        'expectedRevision': 0,
        'reason': 'Agreed test targets'
      });
      for (var i = 0; i < entries.length; i++) {
        final current =
            (await team.activity(entries[i].id)).getOrElse((f) => throw f);
        expect(current.canReview, true);
        entries[i] = (await team.review(current.id, current.revision,
                'verified', 'Confirmed completed work'))
            .getOrElse((f) => throw f);
      }
      summary = (await own.performance(month)).getOrElse((f) => throw f).single;
      expect(summary.meetings, 1);
      expect(summary.viewings, 1);
      expect(summary.meetingTotal, 2);
      expect(summary.sales, 1);
      expect(summary.leases, 1);
      expect(summary.achievement['meetings'], 200);
      expect(summary.transactionValues, {'EGP': 12000.25, 'USD': 12000.25});
      expect(summary.achievement['transactionValue'], 50);
      final managerSummary = (await team.performance(month, team: true))
          .getOrElse((f) => throw f)
          .single;
      expect(managerSummary.meetingTotal, summary.meetingTotal);
      expect(
          (await own.review(entries.first.id, entries.first.revision,
                  'returned', 'Self review forbidden'))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          403);
      expect(
          (await other.review(entries.first.id, entries.first.revision,
                  'returned', 'Other department denied'))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          403);
      expect(
          (await other.activity(entries.first.id))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          404);
      expect(
          (await own.correct(
                  entries.first.id, entries.first.revision, visit('meeting')))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          409);
      final returned = (await team.review(entries.first.id,
              entries.first.revision, 'returned', 'Please clarify outcome'))
          .getOrElse((f) => throw f);
      expect(
          (await own.performance(month))
              .getOrElse((f) => throw f)
              .single
              .meetingTotal,
          1);
      final corrected =
          (await own.correct(returned.id, returned.revision, visit('meeting')))
              .getOrElse((f) => throw f);
      expect(corrected.status, 'pending');
      expect(corrected.review!.status, 'returned');
      expect(corrected.submittedAt, returned.submittedAt);
      expect(
          (await team.review(corrected.id, returned.revision, 'verified',
                  'Stale revision denied'))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          409);
      await team.review(corrected.id, corrected.revision, 'verified',
          'Confirmed corrected work');
      expect(
          (await own.performance(month))
              .getOrElse((f) => throw f)
              .single
              .meetingTotal,
          2);
      expect(
          (await own.create(newSalesId(), deal('sale', '  sale-1  ')))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          409);
      final filtered = (await team.activities(month,
              team: true,
              kind: 'closed-deal',
              status: 'verified',
              employeeId: agent.employee['id']))
          .getOrElse((f) => throw f);
      expect(filtered.length, 2);
      expect(filtered.every((a) => a.kind == 'closed-deal'), true);
      Future<void> rejected(Map<String, dynamic> body, int status) async {
        final response = await agent.client.post<Map<String, dynamic>>(
            '/sales/activities',
            data: body,
            options: Options(validateStatus: (_) => true));
        expect(response.statusCode, status);
      }

      await rejected({
        'id': newSalesId(),
        'activity': {
          ...visit('meeting').toJson(),
          'employeeId': agent.employee['id']
        }
      }, 400);
      await rejected({
        'id': newSalesId(),
        'activity': {...visit('meeting').toJson(), 'activityDate': '2026-02-30'}
      }, 400);
      await rejected({
        'id': newSalesId(),
        'activity': {
          ...visit('meeting').toJson(),
          'activityDate':
              '${int.parse(today.substring(0, 4)) + 1}${today.substring(4)}'
        }
      }, 400);
      await rejected({
        'id': newSalesId(),
        'activity': {...visit('meeting').toJson(), 'followUpDate': '2025-12-31'}
      }, 400);
      await rejected({
        'id': newSalesId(),
        'activity': {...deal('sale', 'Bad-1').toJson(), 'value': 1.001}
      }, 400);
      await rejected({
        'id': newSalesId(),
        'activity': {...visit('viewing').toJson(), 'propertyReference': ''}
      }, 400);
      // Simulate a dropped response after the actual backend has committed.
      final dropping = Dio(
          BaseOptions(baseUrl: base, headers: agent.client.options.headers));
      dropping.interceptors
          .add(InterceptorsWrapper(onResponse: (response, handler) {
        if (response.requestOptions.method == 'POST') {
          handler.reject(DioException(
              requestOptions: response.requestOptions,
              type: DioExceptionType.receiveTimeout));
        } else {
          handler.next(response);
        }
      }));
      final mutation = SalesMutationController(SalesService(client: dropping),
          employeeId: agent.employee['id'],
          getAccess: () => const SalesAccess(canSubmit: true),
          onForbidden: () async {});
      await mutation.create(visit('meeting'));
      expect(mutation.state.action, isA<RequestSuccess<SalesActivity>>());
      expect(mutation.state.pending, isNull);
      expect((await own.activities(month)).getOrElse((f) => throw f).length, 5);
      mutation.dispose();
      dropping.close();
      await admin.patch<Map<String, dynamic>>(
          '/employees/${agent.employee['id']}',
          data: {...agent.employee, 'salesEnabled': false}
            ..remove('id')
            ..remove('employeeNumber'));
      expect((await own.access()).getOrElse((f) => throw f).canSubmit, false);
      expect((await own.activities(month)).getOrElse((f) => throw f).length, 5);
      expect(
          (await own.performance(month))
              .getOrElse((f) => throw f)
              .single
              .meetingTotal,
          2);
      await admin.patch<Map<String, dynamic>>('/departments/Sales/manager',
          data: {'employeeId': null});
      expect((await team.access()).getOrElse((f) => throw f).canReview, false);
      expect(
          (await team.activities(month, team: true))
              .fold((f) => (f as ServerFailure).statusCode, (_) => null),
          403);
      admin.close();
    }, _RealHttp());
  },
      skip: base.isEmpty
          ? 'Requires isolated sales backend; see README.md.'
          : false);
}
