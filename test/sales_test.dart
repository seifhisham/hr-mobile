import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/utils/async_state.dart';
import 'package:hodour/src/data/models/user_model.dart';
import 'package:hodour/src/data/models/sales_activity.dart';
import 'package:hodour/src/services/sales_service.dart';
import 'package:hodour/src/ui/sales/sales_provider.dart';
import 'package:hodour/src/middleware/dio_logging_interceptor.dart';
import 'auth_session_test.dart' show TestAdapter, jsonResponse, profile;

const visit = SalesVisit(
    kind: 'meeting',
    activityDate: '2026-10-07',
    clientName: ' Buyer ',
    purpose: ' Requirements ',
    outcome: 'Viewing arranged');
Map<String, dynamic> salesJson(
        {String id = 'activity-a',
        String status = 'pending',
        int revision = 1,
        String owner = 'employee-a',
        bool canReview = false}) =>
    {
      ...visit.toJson(),
      'id': id,
      'employeeId': owner,
      'employeeName': 'Employee',
      'employeeNumber': 'EMP-000001',
      'department': 'Sales',
      'status': status,
      'revision': revision,
      'canReview': canReview,
      'submittedAt': '2026-10-07T08:00:00Z',
      'updatedAt': '2026-10-07T08:00:00Z',
      'review': null,
    };
Map<String, dynamic> performanceJson() => {
      'employeeId': 'employee-a',
      'employeeName': 'Employee',
      'employeeNumber': 'EMP-000001',
      'department': 'Sales',
      'month': '2026-10',
      'active': true,
      'salesEnabled': true,
      'meetings': 2,
      'viewings': 1,
      'meetingTotal': 3,
      'deals': 1,
      'sales': 1,
      'leases': 0,
      'pending': 1,
      'returned': 1,
      'transactionValues': {'EGP': 2500000.25, 'USD': 12000},
      'target': null,
      'achievement': {
        'meetings': null,
        'deals': 150.0,
        'transactionValue': null
      },
    };
SalesMutationController controller(SalesService service,
        {String owner = 'employee-a',
        SalesAccess access =
            const SalesAccess(canSubmit: true, canReview: true),
        Future<void> Function()? forbidden}) =>
    SalesMutationController(service,
        employeeId: owner,
        getAccess: () => access,
        onForbidden: forbidden ?? () async {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('strict variants, trimming, company date limits and money validation',
      () {
    expect(visit.toJson()['clientName'], 'Buyer');
    expect(visit.toJson().keys, isNot(contains('value')));
    expect(
        visit.validate(startDate: '2026-10-01', today: '2026-10-07'), isNull);
    expect(visit.validate(startDate: '2026-10-08', today: '2026-10-07'),
        'sales.errors.date');
    expect(validSalesDate('2026-02-30'), false);
    expect(
        const SalesVisit(
                kind: 'viewing',
                activityDate: '2026-10-07',
                clientName: 'Buyer',
                purpose: 'Visit',
                outcome: 'Done')
            .validate(startDate: '2026-01-01', today: '2026-10-07'),
        'sales.errors.visit');
    expect(
        const SalesVisit(
                kind: 'meeting',
                activityDate: '2026-10-07',
                clientName: 'Buyer',
                purpose: 'Visit',
                outcome: 'Done',
                followUpDate: '2026-10-06')
            .validate(startDate: '2026-01-01', today: '2026-10-07'),
        'sales.errors.follow_up');
    for (final value in [0, -1, 1.001, 1000000001, double.nan]) {
      expect(
          SalesDeal(
                  activityDate: '2026-10-07',
                  clientName: 'Buyer',
                  propertyReference: 'A12',
                  dealReference: 'Sale-1',
                  transactionType: 'sale',
                  value: value,
                  currency: 'EGP')
              .validate(startDate: '2026-01-01', today: '2026-10-07'),
          'sales.errors.money');
    }
    const deal = SalesDeal(
        activityDate: '2026-10-07',
        clientName: 'Buyer',
        propertyReference: 'A12',
        dealReference: 'Lease-1',
        transactionType: 'lease',
        value: 2500000.25,
        currency: 'EGP');
    expect(deal.validate(startDate: '2026-01-01', today: '2026-10-07'), isNull);
    expect(deal.toJson().keys, isNot(contains('purpose')));
    expect(deal.toJson()['transactionType'], 'lease');
    expect(
        newSalesId(),
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(AppUser.fromJson(profile).employee!.salesEnabled, false);
  });
  test('nullable targets, separate currencies, past reviews and unknown states',
      () {
    final summary = SalesPerformance.fromJson(performanceJson());
    expect(summary.target, isNull);
    expect(summary.achievement['meetings'], isNull);
    expect(summary.achievement['deals'], 150);
    expect(summary.transactionValues.keys, ['EGP', 'USD']);
    final item = SalesActivity.fromJson({
      ...salesJson(),
      'review': const {
        'status': 'returned',
        'reason': 'Correct property',
        'by': 'Manager',
        'byId': 'manager',
        'at': '2026-10-07T09:00:00Z'
      }
    });
    expect(item.status, 'pending');
    expect(item.review!.status, 'returned');
    expect(item.canCorrect('employee-a'), true);
    expect(
        SalesActivity.fromJson(salesJson(status: 'future'))
            .canCorrect('employee-a'),
        false);
    expect(
        SalesActivity.fromJson(salesJson(canReview: true))
            .canVerify('employee-a'),
        false);
    expect(
        SalesActivity.fromJson(salesJson(status: 'verified', canReview: true))
            .canReturn('manager'),
        true);
  });
  test('REST query fields and replacement/review envelopes are exact',
      () async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.httpClientAdapter = TestAdapter((request) {
      if (request.method == 'GET') {
        expect(request.queryParameters, {
          'month': '2026-10',
          'kind': 'viewing',
          'status': 'pending',
          'employeeId': 'employee-a'
        });
        return jsonResponse([]);
      }
      expect(
          request.data.keys.toSet(),
          request.path.endsWith('/review')
              ? {'expectedRevision', 'status', 'reason'}
              : {'expectedRevision', 'activity'});
      expect(request.data['expectedRevision'], 3);
      if (request.path.endsWith('/review')) {
        expect(request.data['reason'], 'Confirmed contract');
      }
      return jsonResponse(salesJson(revision: 4));
    });
    final service = SalesService(client: client);
    expect(
        (await service.activities('2026-10',
                team: true,
                kind: 'viewing',
                status: 'pending',
                employeeId: 'employee-a'))
            .isRight(),
        true);
    await service.correct('activity-a', 3, visit);
    await service.review('activity-a', 3, 'verified', ' Confirmed contract ');
    client.close();
  });
  test('lost POST response reconciles with the same UUID without a second POST',
      () async {
    var posts = 0;
    String? savedId;
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.httpClientAdapter = TestAdapter((request) {
      if (request.method == 'POST') {
        posts++;
        savedId = request.data['id'];
        throw DioException(
            requestOptions: request, type: DioExceptionType.receiveTimeout);
      }
      expect(request.path, '/sales/activities/$savedId');
      return jsonResponse(salesJson(id: savedId!));
    });
    final c = controller(SalesService(client: client));
    await c.create(visit);
    expect(posts, 1);
    expect(c.state.action, isA<RequestSuccess<SalesActivity>>());
    expect(c.state.pending, isNull);
    c.dispose();
    client.close();
  });
  test(
      'genuine 404 permits only original UUID/payload retry; network failure does not',
      () async {
    final ids = <String>[];
    final payloads = <Object>[];
    var missing = false;
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.httpClientAdapter = TestAdapter((request) {
      if (request.method == 'POST') {
        ids.add(request.data['id']);
        payloads.add(request.data['activity']);
        if (ids.length == 1) {
          throw DioException(
              requestOptions: request, type: DioExceptionType.connectionError);
        }
        return jsonResponse(salesJson(id: ids.last), 201);
      }
      if (!missing) {
        throw DioException(
            requestOptions: request, type: DioExceptionType.connectionError);
      }
      return jsonResponse({'message': 'Not found'}, 404);
    });
    final c = controller(SalesService(client: client));
    await c.create(visit);
    await c.retryCreation();
    expect(ids.length, 1);
    missing = true;
    await c.reconcile();
    expect((c.state.pending as SalesPendingCreate).retryAllowed, true);
    await c.retryCreation();
    expect(ids[1], ids[0]);
    expect(payloads[1], payloads[0]);
    c.dispose();
    client.close();
  });
  test(
      'lost correction confirms replacement; stale revision never silently retries PATCH',
      () async {
    var patches = 0;
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.httpClientAdapter = TestAdapter((request) {
      if (request.method == 'PATCH') {
        patches++;
        if (patches == 1) {
          throw DioException(
              requestOptions: request, type: DioExceptionType.receiveTimeout);
        }
        return jsonResponse({'message': 'Refresh before saving'}, 409);
      }
      return jsonResponse(salesJson(revision: 2));
    });
    final c = controller(SalesService(client: client));
    await c.correct(SalesActivity.fromJson(salesJson()), visit);
    expect(c.state.action, isA<RequestSuccess<SalesActivity>>());
    await c.correct(SalesActivity.fromJson(salesJson()), visit);
    expect(patches, 2);
    expect(c.state.notice, 'sales.changed');
    expect(c.state.action, isA<RequestFailure<SalesActivity>>());
    c.dispose();
    client.close();
  });
  test('review guards, permission refresh and disposed account responses',
      () async {
    final response = Completer<ResponseBody>();
    var writes = 0, accessRefreshes = 0;
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.httpClientAdapter = TestAdapter((request) {
      writes++;
      return writes == 1
          ? jsonResponse({'message': 'Access removed'}, 403)
          : response.future;
    });
    final c = controller(SalesService(client: client), owner: 'manager',
        forbidden: () async {
      accessRefreshes++;
    });
    await c.review(
        SalesActivity.fromJson(salesJson(owner: 'manager', canReview: true)),
        'verified',
        'Confirmed work');
    expect(writes, 0);
    await c.review(SalesActivity.fromJson(salesJson(canReview: true)),
        'verified', 'Confirmed work');
    expect(accessRefreshes, 1);
    final pending = c.create(visit);
    c.dispose();
    response.complete(jsonResponse(salesJson(owner: 'manager'), 201));
    await pending;
    client.close();
  });
  test('out-of-order monthly reads do not overwrite newer filters', () async {
    final first = Completer<ResponseBody>();
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.httpClientAdapter = TestAdapter((request) {
      if (request.path.contains('performance')) return jsonResponse([]);
      if (request.queryParameters['month'] == '2026-10') return first.future;
      return jsonResponse([salesJson(id: 'november')]);
    });
    final c = SalesListController(SalesService(client: client),
        month: '2026-10', team: false, enabled: true, onForbidden: () async {});
    await c.filter(month: '2026-11');
    first.complete(jsonResponse([salesJson(id: 'october')]));
    await Future<void>.delayed(Duration.zero);
    expect(
        (c.state.data as RequestSuccess<SalesDashboard>)
            .data
            .activities
            .single
            .id,
        'november');
    c.dispose();
    client.close();
  });
  test('sales errors and payloads stay out of network logs', () async {
    final logs = <Object>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost/api'));
    client.interceptors.add(DioLoggingInterceptor(logPrint: logs.add));
    client.httpClientAdapter = TestAdapter((request) =>
        jsonResponse({'message': 'Private Buyer contract Sale-1'}, 409));
    await SalesService(client: client).create(newSalesId(), visit);
    expect(logs, isEmpty);
    client.close();
  });
}
