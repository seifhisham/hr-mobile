import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:hrmobile/src/theme/theme_mode_provider.dart';
import 'package:hrmobile/src/services/notifications_service.dart';
import 'package:hrmobile/src/ui/notifications/notifications_provider.dart';
import 'dart:convert';
import 'package:image/image.dart' as image;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hrmobile/src/app.dart';
import 'package:hrmobile/src/ui/notifications/notifications_screen.dart';
import 'package:hrmobile/src/ui/requests/request_details_screen.dart';
import 'package:hrmobile/src/ui/requests/request_widgets.dart';
import 'package:hrmobile/src/ui/requests/new_request_screen.dart';
import 'package:hrmobile/src/services/request_attachment_service.dart';
import 'package:hrmobile/src/data/models/employee_request.dart';
import 'package:hrmobile/src/ui/requests/department_reviews_screen.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/actions/app_button.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/display/app_card.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/navigation/app_bottom_nav_bar.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/actions/app_text_button.dart';
import 'package:hrmobile/src/data/repositories/auth_repository_impl.dart';
import 'package:hrmobile/src/services/auth_service.dart';
import 'package:hrmobile/src/ui/auth/providers/session_provider.dart';
import 'package:hrmobile/src/routing/app_router.dart';
import 'package:hrmobile/src/services/attendance_service.dart';
import 'package:hrmobile/src/ui/attendance/attendance_provider.dart';
import 'package:hrmobile/src/ui/attendance/attendance_work_progress.dart';
import 'package:hrmobile/src/ui/home/home_header.dart';
import 'package:hrmobile/src/utils/utils.dart';
import 'package:hrmobile/src/shared/widgets/toast/toast_card.dart';
import 'attendance_test.dart' show policyJson, recordJson, FakeCapture;
import 'requests_test.dart' show requestJson;
import 'notifications_test.dart' show notificationJson;
import 'sales_test.dart' show salesJson, performanceJson;
import 'package:hrmobile/src/ui/sales/sales_form_screen.dart';
import 'package:hrmobile/src/ui/sales/sales_details_screen.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/inputs/app_dropdown.dart';
import 'package:hrmobile/src/services/requests_service.dart';
import 'package:hrmobile/src/ui/requests/requests_provider.dart';
import 'package:hrmobile/src/services/sales_service.dart';
import 'package:hrmobile/src/ui/sales/sales_provider.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/inputs/app_text_area.dart';
import 'package:hrmobile/src/ui/attendance/attendance_evidence.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_session_test.dart'
    show TestAdapter, jsonResponse, profile, schedules;

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, Map<String, dynamic>> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      values[locale.languageCode]!;
}

class _AttachmentPicker extends RequestAttachmentService {
  int picks = 0;
  @override
  FutureEither<RequestAttachment?> pick() => runTask(() async {
        picks++;
        return RequestAttachment(
            name: 'document-$picks.pdf',
            mimeType: 'application/pdf',
            content: base64Encode('%PDF-1.4'.codeUnits));
      }, operation: 'test.pick_attachment');
}

void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester,
      {bool savedSession = false,
      bool noEmployee = false,
      bool offline = false,
      bool salesSubmit = false,
      bool salesReview = false,
      List<Map<String, dynamic>> salesActivities = const [],
      Map<String, dynamic>? salesPerformance,
      Locale locale = const Locale('en'),
      List<Map<String, dynamic>> requests = const [],
      List<Map<String, dynamic>> notifications = const [],
      List<Map<String, dynamic>> managedRequests = const [],
      bool removeNotificationOnRead = false,
      List<Map<String, dynamic>>? attendanceRecords,
      bool Function()? attendanceUnavailable,
      FakeCapture? capture,
      RequestAttachmentService? attachmentPicker,
      void Function(RequestOptions)? onRequest,
      Future<void> Function(RequestOptions)? beforeRequest}) async {
    final attendanceItems = attendanceRecords ?? [recordJson(closed: true)];
    final requestItems = List<Map<String, dynamic>>.of(requests);
    final notificationItems = List<Map<String, dynamic>>.of(notifications);
    final salesItems = List<Map<String, dynamic>>.of(salesActivities);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues(
        savedSession ? {AuthService.tokenKey: 'stored-token'} : {});
    await EasyLocalization.ensureInitialized();
    final translations = <String, Map<String, dynamic>>{};
    await tester.runAsync(() async {
      for (final language in ['en', 'ar']) {
        translations[language] = jsonDecode(await rootBundle.loadString(
            'assets/translations/$language.json')) as Map<String, dynamic>;
      }
    });
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3002/api'));
    if (beforeRequest != null) {
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        await beforeRequest(options);
        handler.next(options);
      }));
    }
    client.httpClientAdapter = TestAdapter((request) {
      onRequest?.call(request);
      if (request.path == '/sales/access') {
        return jsonResponse({
          'canSubmit': salesSubmit,
          'canReview': salesReview,
          'canSetTargets': false
        });
      }
      if (request.path.startsWith('/sales/performance')) {
        return jsonResponse(
            salesItems.isEmpty ? [] : [salesPerformance ?? performanceJson()]);
      }
      if (request.path == '/sales/activities' && request.method == 'POST') {
        final entry = {
          ...salesJson(id: request.data['id']),
          ...request.data['activity'] as Map<String, dynamic>
        };
        salesItems.add(entry);
        return jsonResponse(entry, 201);
      }
      if (request.path == '/sales/activities' ||
          request.path == '/sales/activities/me') {
        return jsonResponse(salesItems
            .where((a) =>
                (request.queryParameters['kind'] == null ||
                    a['kind'] == request.queryParameters['kind']) &&
                (request.queryParameters['status'] == null ||
                    a['status'] == request.queryParameters['status']) &&
                (request.queryParameters['employeeId'] == null ||
                    a['employeeId'] == request.queryParameters['employeeId']))
            .toList());
      }
      if (request.path.startsWith('/sales/activities/')) {
        final index =
            salesItems.indexWhere((a) => a['id'] == request.path.split('/')[3]);
        if (index == -1) {
          return jsonResponse({'message': 'Unavailable activity'}, 404);
        }
        if (request.method == 'PATCH') {
          salesItems[index] = {
            ...salesItems[index],
            'revision': (salesItems[index]['revision'] as int) + 1,
            if (request.path.endsWith('/review')) ...{
              'status': request.data['status'],
              'review': {
                'status': request.data['status'],
                'reason': request.data['reason'],
                'by': 'Test Manager',
                'byId': 'user-a',
                'at': '2026-10-07T10:00:00Z'
              }
            } else ...{
              'status': 'pending',
              ...request.data['activity'] as Map<String, dynamic>
            }
          };
        }
        return jsonResponse(salesItems[index]);
      }
      if (request.path == '/notifications') {
        return jsonResponse({
          'items': notificationItems,
          'unreadCount':
              notificationItems.where((n) => n['readAt'] == null).length
        });
      }
      if (request.path.startsWith('/notifications/') &&
          request.path.endsWith('/read')) {
        final id = Uri.decodeComponent(request.path.split('/')[2]);
        final index = notificationItems.indexWhere((n) => n['id'] == id);
        if (removeNotificationOnRead || index == -1) {
          notificationItems.removeWhere((n) => n['id'] == id);
          return jsonResponse({'message': 'Notification not found'}, 404);
        }
        notificationItems[index] = {
          ...notificationItems[index],
          'readAt': notificationItems[index]['readAt'] ?? '2026-10-06T10:10:00Z'
        };
        return jsonResponse(notificationItems[index]);
      }
      if (request.path.endsWith('/manager-review')) {
        final index = managedRequests
            .indexWhere((r) => r['id'] == request.path.split('/')[2]);
        managedRequests[index] = {
          ...managedRequests[index],
          'managerStage': request.data['status'],
          'managerReview': {
            'status': request.data['status'],
            'reason': request.data['reason'],
            'employeeId': 'employee-a',
            'reviewedBy': 'Test Manager',
            'reviewedAt': '2026-10-07T10:00:00Z'
          }
        };
        return jsonResponse(managedRequests[index]);
      }
      if (request.path == '/requests/managed') {
        return jsonResponse(managedRequests);
      }
      if (offline) {
        throw DioException(
            requestOptions: request, type: DioExceptionType.connectionError);
      }
      if (request.path == '/auth/login') {
        return jsonResponse(
            {'token': 'new-token', 'user': profile['user']}, 201);
      }
      if (request.path == '/auth/me') {
        return jsonResponse(
            noEmployee ? {...profile, 'employee': null} : profile);
      }
      if (request.path == '/requests/me') return jsonResponse(requestItems);
      if (request.path == '/requests' && request.method == 'POST') {
        final created = {
          ...requestJson(),
          ...request.data as Map<String, dynamic>
        };
        requestItems.insert(0, created);
        return jsonResponse(created, 201);
      }
      if (request.path.endsWith('/withdraw')) {
        final id = request.path.split('/')[2];
        final index = requestItems.indexWhere((r) => r['id'] == id);
        requestItems[index] = {
          ...requestItems[index],
          'status': 'withdrawn',
          'lastChange': {
            'action': 'withdraw',
            'reason': request.data['reason'],
            'by': 'Test Employee',
            'at': '2026-10-06T10:02:00Z'
          }
        };
        return jsonResponse(requestItems[index]);
      }
      if (request.path == '/schedules') return jsonResponse(schedules);
      if (request.path == '/attendance/check-in' ||
          request.path.endsWith('/check-out')) {
        final record = recordJson(closed: request.path.endsWith('/check-out'));
        attendanceItems.clear();
        attendanceItems.add(record);
        return jsonResponse(record);
      }
      if (request.path == '/attendance/me') {
        if (attendanceUnavailable?.call() ?? false) {
          return jsonResponse({'message': 'Attendance unavailable'}, 503);
        }
        return jsonResponse({
          'workDate': '2026-10-05',
          'schedule': schedules.first,
          'records': attendanceItems
        });
      }
      if (request.path.endsWith('/evidence')) return jsonResponse([]);
      if (request.path == '/attendance/policy') return jsonResponse(policyJson);
      if (request.path == '/auth/password') {
        return jsonResponse({'message': 'Current password is incorrect'}, 401);
      }
      return jsonResponse({'message': 'Signed out'}, 201);
    });
    final service = AuthService(client: client)..initialize();
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      startLocale: locale,
      path: 'assets/translations',
      assetLoader: _Translations(translations),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      child: ProviderScope(
          overrides: [
            if (attachmentPicker != null)
              requestAttachmentServiceProvider
                  .overrideWithValue(attachmentPicker),
            salesRepositoryProvider
                .overrideWithValue(SalesService(client: client)),
            if (capture != null)
              attendanceCaptureProvider.overrideWithValue(capture),
            notificationsRepositoryProvider
                .overrideWithValue(NotificationsService(client: client)),
            requestsRepositoryProvider
                .overrideWithValue(RequestsService(client: client)),
            attendanceEvidenceServiceProvider
                .overrideWithValue(AttendanceService(client: client)),
            attendanceRepositoryProvider
                .overrideWithValue(AttendanceService(client: client)),
            authRepositoryProvider
                .overrideWithValue(AuthRepositoryImpl(service: service))
          ],
          child: const RepaintBoundary(
              key: ValueKey('design-preview'), child: App())),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(App)));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      client.close(force: true);
    });
    return container;
  }

  testWidgets(
      'sales form switches schemas and submits completed work with company date',
      (tester) async {
    final writes = <RequestOptions>[];
    final container = await pumpApp(tester,
        savedSession: true, salesSubmit: true, onRequest: (r) {
      if (r.method == 'POST' && r.path == '/sales/activities') writes.add(r);
    });
    container.read(appRouterProvider).goNamed('newSalesActivity');
    await tester.pumpAndSettle();
    expect(find.byType(SalesFormScreen), findsOneWidget);
    Future<void> fill(String key, String value) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await fill('clientName', 'Buyer');
    await fill('purpose', 'Meeting requirements');
    await fill('outcome', 'Interested in apartment');
    final kind = find.byWidgetPredicate(
        (w) => w is AppDropdown<String> && w.label == 'Activity type');
    tester.widget<AppDropdown<String>>(kind).onChanged('closed-deal');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('purpose')), findsNothing);
    await fill('propertyReference', 'Unit A12');
    await fill('dealReference', 'Lease-1');
    await fill('value', '12000.25');
    final transaction = find.byWidgetPredicate(
        (w) => w is AppDropdown<String> && w.label == 'Contract type');
    tester.widget<AppDropdown<String>>(transaction).onChanged('lease');
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(AppButton, 'Submit for verification');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(writes.length, 1);
    expect(writes.single.data['activity']['activityDate'], profile['today']);
    expect(writes.single.data['activity']['transactionType'], 'lease');
    expect(writes.single.data['activity'].keys, isNot(contains('purpose')));
    expect(find.byType(SalesDetailsScreen), findsOneWidget);
    expect(find.text('Pending verification'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'review-only manager can verify team sales with clear final-performance confirmation',
      (tester) async {
    final writes = <RequestOptions>[];
    final container = await pumpApp(tester,
        savedSession: true,
        salesReview: true,
        salesActivities: [salesJson(owner: 'team-employee', canReview: true)],
        onRequest: (r) {
      if (r.method == 'PATCH' && r.path.endsWith('/review')) writes.add(r);
    });
    container.read(appRouterProvider).goNamed('sales');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Register activity'), findsNothing);
    expect(
        find.widgetWithText(AppButton, 'Team sales reviews'), findsOneWidget);
    container.read(appRouterProvider).goNamed('salesActivityDetails',
        pathParameters: {'id': 'activity-a'},
        queryParameters: {'team': 'true'});
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(
        find.byType(TextFormField), 'Confirmed completed work');
    final verify = find.widgetWithText(AppButton, 'Verify activity');
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Confirm this completed activity? It will count toward monthly performance.'),
        findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(writes.single.data, {
      'expectedRevision': 1,
      'status': 'verified',
      'reason': 'Confirmed completed work'
    });
    expect(find.text('Verified'), findsWidgets);
    expect(find.widgetWithText(AppButton, 'Verify activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sales history stays readable when disabled; self review hidden and logout clears account state',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        salesReview: true,
        salesActivities: [salesJson(canReview: true)]);
    container
        .read(appRouterProvider)
        .goNamed('salesActivityDetails', pathParameters: {'id': 'activity-a'});
    await tester.pumpAndSettle();
    expect(find.text('Buyer'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Verify activity'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Correct activity'), findsNothing);
    container.read(authRepositoryProvider).logout();
    await tester.pumpAndSettle();
    expect(find.text('Buyer'), findsNothing);
    expect(container.read(salesMutationProvider).pending, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sales English and Arabic screens fit dark mode, landscape and large text',
      (tester) async {
    for (final language in ['en', 'ar']) {
      final container = await pumpApp(tester,
          savedSession: true,
          salesSubmit: true,
          salesReview: true,
          locale: Locale(language),
          salesActivities: [salesJson()]);
      container.read(appRouterProvider).goNamed('sales');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (language == 'ar') {
        expect(Directionality.of(tester.element(find.text('سجل الأنشطة'))),
            TextDirection.rtl);
      }
      await container.read(themeModeProvider.notifier).setDark(true);
      tester.view.physicalSize = const Size(812, 375);
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      for (final route in ['sales', 'teamSales', 'newSalesActivity']) {
        container.read(appRouterProvider).goNamed(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'sales month selector and foreground refresh use current API data',
      (tester) async {
    var accessReads = 0, listReads = 0;
    final container = await pumpApp(tester,
        savedSession: true,
        salesSubmit: true,
        salesActivities: [salesJson()], onRequest: (request) {
      if (request.path == '/sales/access') accessReads++;
      if (request.path == '/sales/activities/me') listReads++;
    });
    container.read(appRouterProvider).goNamed('sales');
    await tester.pumpAndSettle();
    final monthButton = find.widgetWithText(AppTextButton, 'October 2026');
    await tester.ensureVisible(monthButton);
    await tester.tap(monthButton);
    await tester.pumpAndSettle();
    final month = find
        .byWidgetPredicate((w) => w is AppDropdown<int> && w.label == 'Month');
    tester.widget<AppDropdown<int>>(month).onChanged(9);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(container.read(salesListProvider(false)).month, '2026-09');
    final previousAccess = accessReads, previousLists = listReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(accessReads, greaterThan(previousAccess));
    expect(listReads, greaterThan(previousLists));
    expect(container.read(salesListProvider(false)).month, '2026-09');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'returned sales correction retains review context and sends a full revision-aware replacement',
      (tester) async {
    final writes = <RequestOptions>[];
    final container = await pumpApp(tester,
        savedSession: true,
        salesSubmit: true,
        salesActivities: [
          {
            ...salesJson(status: 'returned', revision: 3),
            'activityDate': profile['today'],
            'review': {
              'status': 'returned',
              'reason': 'Clarify the outcome',
              'by': 'Manager',
              'byId': 'manager',
              'at': '2026-10-07T09:00:00Z'
            }
          }
        ], onRequest: (request) {
      if (request.method == 'PATCH' &&
          request.path == '/sales/activities/activity-a') {
        writes.add(request);
      }
    });
    container
        .read(appRouterProvider)
        .goNamed('editSalesActivity', pathParameters: {'id': 'activity-a'});
    await tester.pumpAndSettle();
    final outcome = find.byKey(const ValueKey('outcome'));
    await tester.ensureVisible(outcome);
    await tester.enterText(outcome, 'Client confirmed requirements');
    final save = find.widgetWithText(AppButton, 'Save and resubmit');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(writes.single.data['expectedRevision'], 3);
    expect(writes.single.data['activity']['outcome'],
        'Client confirmed requirements');
    expect(find.text('Pending verification'), findsOneWidget);
    expect(find.text('Previous review'), findsOneWidget);
    expect(find.text('Clarify the outcome'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'notifications badge, unread filter and own request link use fresh data',
      (tester) async {
    final calls = <RequestOptions>[];
    final request = requestJson();
    final container = await pumpApp(tester,
        savedSession: true,
        requests: [request],
        notifications: [
          {...notificationJson(), 'requestId': request['id']}
        ],
        onRequest: calls.add);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Request approved'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(find.text('You are all caught up.'), findsOneWidget);
    expect(container.read(notificationsProvider).inbox!.unreadCount, 0);
    expect(calls.where((r) => r.method == 'PATCH').single.data, isNull);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final before = calls.where((r) => r.path == '/requests/me').length;
    await tester.ensureVisible(find.text('Open details'));
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path == '/requests/me').length,
        greaterThan(before));
    expect(find.byType(RequestDetailsScreen), findsOneWidget);
    expect(find.text('Request details'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed alerts refresh the inbox without opening a stale link',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        notifications: [notificationJson()],
        removeNotificationOnRead: true);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This notification is no longer available. The inbox has been refreshed.'),
        findsOneWidget);
    expect(container.read(notificationsProvider).inbox!.items, isEmpty);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets(
      'notification refresh runs in foreground and stops in background and on logout',
      (tester) async {
    var loads = 0;
    final container =
        await pumpApp(tester, savedSession: true, onRequest: (request) {
      if (request.path == '/notifications') loads++;
    });
    final first = loads;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(loads, greaterThan(first));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = loads;
    await tester.pump(const Duration(seconds: 65));
    expect(loads, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(loads, greaterThan(paused));
    container.read(authRepositoryProvider).logout();
    await tester.pumpAndSettle();
    final signedOut = loads;
    await tester.pump(const Duration(seconds: 31));
    expect(loads, signedOut);
    expect(container.read(notificationsProvider).inbox, isNull);
    expect(find.byTooltip('Notifications'), findsNothing);
  });

  for (final status in ['approved', 'rejected']) {
    testWidgets('manager alert $status opens a server-authorized bottom sheet',
        (tester) async {
      final request = {
        ...requestJson(),
        'employeeId': 'other-employee',
        'employeeName': 'Department Colleague',
        'managerStage': 'pending',
        'managerEmployeeId': 'employee-a'
      };
      await pumpApp(tester, savedSession: true, managedRequests: [
        request
      ], notifications: [
        {
          ...notificationJson(type: 'manager-review-required'),
          'requestId': request['id']
        }
      ]);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Department Colleague'), findsOneWidget);
      expect(find.text('Withdraw request'), findsNothing);
      final approval = find.text(status == 'approved'
          ? 'Recommend approval to HR'
          : 'Recommend rejection to HR');
      await tester.ensureVisible(approval);
      await tester.tap(approval);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Use 5–500 trimmed characters for the recommendation reason.'),
          findsOneWidget);
      await tester.enterText(find.byType(AppTextArea), 'Coverage arranged');
      await tester.ensureVisible(approval);
      await tester.tap(approval);
      await tester.pumpAndSettle();
      expect(approval, findsNothing);
      expect(find.text('Recommend rejection to HR'), findsNothing);
      expect(find.text('Coverage arranged'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Arabic dark manager form supports large text landscape and rejection',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        locale: const Locale('ar'),
        managedRequests: [
          {
            ...requestJson(),
            'employeeId': 'colleague',
            'managerStage': 'pending',
            'managerEmployeeId': 'employee-a'
          }
        ]);
    container
        .read(appRouterProvider)
        .goNamed('managedRequestDetails', pathParameters: {'id': 'request-a'});
    await tester.pumpAndSettle();
    await container.read(themeModeProvider.notifier).setDark(true);
    tester.view.physicalSize = const Size(844, 390);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextArea), 'لا تتوفر تغطية للقسم');
    await tester.pumpAndSettle();
    final reject = find.text('التوصية بالرفض للموارد البشرية');
    await tester.ensureVisible(reject);
    await tester.pumpAndSettle();
    await tester.tap(reject);
    await tester.pumpAndSettle();
    expect(reject, findsNothing);
    expect(find.text('لا تتوفر تغطية للقسم'), findsOneWidget);
    expect(
        container.read(managedRequestsProvider).items.single.status, 'pending');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stale manager alerts cannot open an unauthorized department queue',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        notifications: [notificationJson(type: 'manager-review-required')]);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(DepartmentReviewsScreen), findsNothing);
    expect(container.read(managedRequestsProvider).items, isEmpty);
    expect(container.read(notificationsProvider).inbox!.unreadCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request sheet supports dark RTL and large landscape text',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        locale: const Locale('ar'),
        notifications: [
          {
            ...notificationJson(type: 'manager-review-required'),
            'requestId': 'request-a'
          }
        ],
        managedRequests: [
          {
            ...requestJson(),
            'employeeId': 'colleague',
            'managerStage': 'pending',
            'managerEmployeeId': 'employee-a'
          }
        ]);
    await container.read(themeModeProvider.notifier).setDark(true);
    container.read(appRouterProvider).goNamed('notifications');
    await tester.pumpAndSettle();
    await tester.tap(find.text('فتح التفاصيل'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('توصيتك للموارد البشرية'), findsOneWidget);
    tester.view.physicalSize = const Size(812, 375);
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Arabic dark notifications fit a small phone', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester,
        savedSession: true,
        locale: const Locale('ar'),
        notifications: [
          {
            ...notificationJson(),
            'title': 'تمت الموافقة على الطلب',
            'message': 'تمت الموافقة على إجازتك.'
          }
        ]);
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('الإشعارات'));
    await tester.pumpAndSettle();
    expect(find.text('تمت الموافقة على الطلب'), findsOneWidget);
    expect(
        Directionality.of(tester.element(find.text('تمت الموافقة على الطلب'))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(812, 375);
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme button switches both ways and restores the saved choice',
      (tester) async {
    final container = await pumpApp(tester, savedSession: true);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system);
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await tester.runAsync(() async {
      expect(await restored.read(themeModeProvider.future), ThemeMode.dark);
    });
    container.read(appRouterProvider).goNamed('account');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light);
    await tester.runAsync(() async {
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(ThemeModeController.preferenceKey), isFalse);
    });
  });

  testWidgets(
      'Sales separates verified results and review work and labels target progress',
      (tester) async {
    final performance = {
      ...performanceJson(),
      'target': {
        'employeeId': 'employee-a',
        'month': '2026-10',
        'meetings': 6,
        'deals': 2,
        'transactionValue': 24000,
        'currency': 'USD',
        'revision': 1,
        'reason': 'Monthly goals',
        'updatedBy': 'HR',
        'updatedAt': '2026-10-01T08:00:00Z',
      },
      'achievement': {
        'meetings': 50.0,
        'deals': 50.0,
        'transactionValue': 50.0
      },
    };
    final container = await pumpApp(tester,
        savedSession: true,
        salesSubmit: true,
        salesActivities: [salesJson()],
        salesPerformance: performance);
    container.read(appRouterProvider).goNamed('sales');
    await tester.pumpAndSettle();
    final verifiedCard = find
        .ancestor(
            of: find.text('Verified results'), matching: find.byType(AppCard))
        .first;
    expect(
        find.descendant(
            of: verifiedCard, matching: find.text('Client meetings')),
        findsOneWidget);
    expect(
        find.descendant(
            of: verifiedCard, matching: find.text('Property viewings')),
        findsOneWidget);
    expect(find.descendant(of: verifiedCard, matching: find.text('Sales')),
        findsOneWidget);
    expect(find.descendant(of: verifiedCard, matching: find.text('Leases')),
        findsOneWidget);
    expect(
        find.descendant(
            of: verifiedCard, matching: find.text('Pending verification')),
        findsNothing);
    final reviewCard = find
        .ancestor(
            of: find.text('Not counted yet'), matching: find.byType(AppCard))
        .first;
    expect(
        find.descendant(
            of: reviewCard, matching: find.text('Pending verification')),
        findsOneWidget);
    expect(
        find.descendant(
            of: reviewCard, matching: find.text('Returned for correction')),
        findsOneWidget);
    expect(find.text('Verified: 3 / Target: 6'), findsOneWidget);
    expect(find.text('Verified: USD 12,000.00 / Target: USD 24,000.00'),
        findsOneWidget);
    expect(find.text('Counts USD contracts only.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets(
        'Sales cards support ${locale.languageCode} dark mode and large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await pumpApp(tester,
          savedSession: true,
          locale: locale,
          salesSubmit: true,
          salesReview: true,
          salesActivities: [
            salesJson(),
            salesJson(id: 'verified-a', status: 'verified')
          ]);
      container.read(appRouterProvider).goNamed('sales');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('sales.target_not_set'.tr()), findsOneWidget);
      expect(find.text('sales.unavailable'.tr()), findsNothing);
      final scroll = find
          .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable))
          .first;
      for (var step = 0; step < 14; step++) {
        await tester.drag(scroll, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('sales.statuses.verified'.tr()), findsWidgets);
    });
  }

  testWidgets('redesigned workspace navigation and visual previews',
      (tester) async {
    const previews = bool.fromEnvironment('DESIGN_PREVIEWS');
    const previewArabic = bool.fromEnvironment('DESIGN_ARABIC');
    const previewCompleted = bool.fromEnvironment('DESIGN_HOME_COMPLETE');
    if (previews) {
      await tester.runAsync(() async {
        const fontDirectory = String.fromEnvironment('DESIGN_FONT_DIR');
        const arabicFont = String.fromEnvironment('DESIGN_ARABIC_FONT');
        final text = FontLoader('Roboto');
        if (previewArabic) {
          text.addFont(File(arabicFont)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
        } else {
          for (final weight in ['Regular', 'Medium', 'Bold']) {
            text.addFont(File('$fontDirectory/Roboto/Roboto-$weight.ttf')
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)));
          }
        }
        await text.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(File('$fontDirectory/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
        await icons.load();
      });
    }
    if (previewArabic) {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    }
    final container = await pumpApp(tester,
        savedSession: true,
        attendanceRecords: previews && !previewCompleted ? [] : null,
        locale: previewArabic ? const Locale('ar') : const Locale('en'),
        salesSubmit: previews,
        salesReview: previews,
        salesActivities: previews
            ? [
                salesJson(),
                {
                  ...salesJson(id: 'viewing-a', status: 'verified'),
                  'kind': 'viewing',
                  'propertyReference': 'Building A / Unit 12'
                }
              ]
            : [],
        notifications: previews ? [notificationJson()] : []);
    for (final route in [
      'home',
      'attendance',
      'requests',
      'account',
      'notifications',
      'newRequest',
      'sales',
      'teamSales',
      'newSalesActivity',
      'changePassword',
      'login'
    ]) {
      if (route == 'login') {
        container.read(authRepositoryProvider).logout();
      } else {
        container.read(appRouterProvider).goNamed(route);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (previews) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('design-preview')));
        await tester.runAsync(() async {
          final preview = await boundary.toImage(pixelRatio: 2);
          final bytes =
              await preview.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('artifacts/redesign')
            ..createSync(recursive: true);
          await File(
                  '${folder.path}/$route${previewArabic ? '-ar-dark' : ''}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          preview.dispose();
        });
      }
    }
  });

  testWidgets(
      'unauthenticated users see HR guidance and protected routes redirect to login',
      (tester) async {
    final container = await pumpApp(tester);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.textContaining('Accounts are provided by HR'), findsOneWidget);
    expect(find.text('Sign Up'), findsNothing);
    expect(find.text('Forgot Password'), findsNothing);
    container.read(appRouterProvider).goNamed('account');
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets(
      'login reaches profile; wrong current password retains form and session',
      (tester) async {
    final container = await pumpApp(tester);
    await tester.enterText(
        find.byType(TextFormField).first, 'employee@example.test');
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Test Employee'), findsOneWidget);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('00123456789012'), findsOneWidget);
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'incorrect');
    await tester.enterText(fields.at(1), 'new-password');
    await tester.enterText(fields.at(2), 'new-password');
    await tester.ensureVisible(find.byType(AppButton).last);
    await tester.tap(find.byType(AppButton).last);
    await tester.pumpAndSettle();
    expect(find.text('Current password is incorrect'), findsOneWidget);
    expect(find.text('incorrect'), findsOneWidget);
    expect(find.text('new-password'), findsNWidgets(2));
    expect(container.read(sessionProvider), isA<SessionAuthenticated>());
  });

  testWidgets('stored session stays recoverable when validation is offline',
      (tester) async {
    final container = await pumpApp(tester, savedSession: true, offline: true);
    expect(container.read(sessionProvider), isA<SessionUnavailable>());
    expect(find.text('Unable to validate your session'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Test Employee'), findsNothing);
  });

  testWidgets('navigation stays mounted and stationary between workspace pages',
      (tester) async {
    await pumpApp(tester, savedSession: true);
    final dock = find.byType(AppBottomNavBar);
    final element = tester.element(dock);
    final position = tester.getTopLeft(dock);
    for (final label in ['Check-In', 'Requests', 'Account', 'Sales', 'Home']) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      expect(find.byType(AppBottomNavBar), findsOneWidget);
      expect(tester.element(dock), same(element));
      expect(tester.getTopLeft(dock), position);
      await tester.pumpAndSettle();
      expect(tester.element(dock), same(element));
      expect(tester.getTopLeft(dock), position);
      expect(tester.getRect(find.byType(Scaffold).last).bottom,
          closeTo(tester.getRect(find.byType(Scaffold).first).bottom, 1),
          reason: 'The page canvas continues behind the floating dock');
      final scrollView = find.byType(SingleChildScrollView).first;
      expect(tester.getRect(scrollView).bottom,
          closeTo(tester.getRect(find.byType(Scaffold).first).bottom, 1),
          reason:
              'Content scrolls behind the dock without a rectangular cutoff');
      final scrollPadding = tester
          .widget<SingleChildScrollView>(scrollView)
          .padding!
          .resolve(TextDirection.ltr);
      expect(scrollPadding.bottom, greaterThan(tester.getSize(dock).height),
          reason: 'The last content can scroll clear of the dock');
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Home startup loads attendance once', (tester) async {
    final paths = <String>[];
    await pumpApp(tester,
        savedSession: true, onRequest: (request) => paths.add(request.path));
    expect(paths.where((path) => path == '/attendance/me'), hasLength(1));
    expect(find.text('Checked out'), findsOneWidget);
    expect(paths.where((path) => path == '/attendance/policy'), hasLength(1));
  });
  testWidgets('Home restores elapsed work ring in Arabic and dark mode',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        locale: const Locale('ar'),
        attendanceRecords: [
          {
            ...recordJson(),
            'checkIn': DateTime.now()
                .subtract(const Duration(hours: 4))
                .toUtc()
                .toIso8601String(),
          }
        ]);
    expect(find.byType(AttendanceWorkProgress), findsOneWidget);
    expect(find.textContaining('مدة العمل: 04:00:'), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(find.descendant(
        of: find.byType(AttendanceWorkProgress),
        matching: find.byType(CircularProgressIndicator)));
    expect(ring.value, closeTo(0.5, 0.001));
    await container.read(themeModeProvider.notifier).setDark(true);
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceWorkProgress), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'Home shows server overnight workday and saved record timezone, blocks closed day',
      (tester) async {
    await pumpApp(tester, savedSession: true, attendanceRecords: [
      {...recordJson(closed: true), 'timezone': 'Asia/Dubai'}
    ]);
    expect(find.text('2026-10-05'), findsOneWidget);
    expect(
        find.textContaining('Company calendar date: 2026-10-06'), findsNothing);
    expect(find.text('Checked out'), findsOneWidget);
    expect(find.text('02:00:00'), findsOneWidget);
    expect(find.text('08:00:00'), findsOneWidget);
    expect(find.text('Asia/Dubai'), findsOneWidget);
    expect(find.text('EMP-000001'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(HomeHeader), matching: find.text('2026-10-05')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(HomeHeader),
            matching: find.text('Night shift: 22:00 – 06:00')),
        findsOneWidget);
    expect(find.byIcon(Icons.login_rounded), findsNothing);
    expect(find.byIcon(Icons.logout_rounded), findsNothing);
  });
  testWidgets(
      'Home performs fresh check-in and exact-record check-out using shared controller',
      (tester) async {
    final capture = FakeCapture();
    final paths = <String>[];
    await pumpApp(tester,
        savedSession: true,
        attendanceRecords: [],
        capture: capture, onRequest: (request) {
      if (request.method == 'POST') paths.add(request.path);
    });
    expect(find.text('Welcome back,'), findsOneWidget);
    expect(find.text('Not checked in'), findsOneWidget);
    expect(find.byIcon(Icons.login_rounded), findsOneWidget);
    expect(find.byType(AttendanceWorkProgress), findsNothing);
    await tester.ensureVisible(find.text('Check in'));
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    expect(find.text('Check out'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    expect(find.byType(AttendanceWorkProgress), findsOneWidget);
    expect(find.textContaining('Time worked:'), findsOneWidget);
    await tester.ensureVisible(find.text('Check out'));
    await tester.tap(find.text('Check out'));
    await tester.pumpAndSettle();
    expect(
        paths, ['/attendance/check-in', '/attendance/owned-record/check-out']);
    expect(capture.calls, 2);
    expect(find.text('Checked out'), findsOneWidget);
    expect(find.byType(AttendanceWorkProgress), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });
  for (final checkOut in [false, true]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
          'attendance rings repel on ${checkOut ? 'check-out' : 'check-in'} press, reduced motion $reducedMotion',
          (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reducedMotion);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final capture = FakeCapture()..value = null;
        await pumpApp(tester,
            savedSession: true,
            capture: capture,
            locale: Locale(checkOut ? 'ar' : 'en'),
            attendanceRecords: checkOut ? [recordJson()] : []);
        final label =
            (checkOut ? 'attendance.check_out' : 'attendance.check_in').tr();
        final button = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        await tester.ensureVisible(button);
        final before = tester.getRect(button);
        double scale(String key) => tester
            .widget<Transform>(find.byKey(ValueKey(key)))
            .transform
            .entry(0, 0);
        expect(scale('attendance-outer-ring'), 1);
        final gesture = await tester.startGesture(tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 110));
        await tester.pump(const Duration(milliseconds: 70));
        expect(tester.getRect(button), before, reason: 'Only the rings move');
        if (reducedMotion) {
          expect(scale('attendance-outer-ring'), 1);
          expect(scale('attendance-inner-ring'), 1);
        } else {
          expect(scale('attendance-outer-ring'), greaterThan(1));
          expect(scale('attendance-inner-ring'), greaterThan(1));
          expect(scale('attendance-outer-ring'),
              greaterThan(scale('attendance-inner-ring')));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scale('attendance-outer-ring'), 1);
        expect(scale('attendance-inner-ring'), 1);
        expect(capture.calls, 1, reason: 'The action still fires exactly once');
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final checkOut in [false, true]) {
    testWidgets(
        'location off shows top toast for ${checkOut ? 'check-out' : 'check-in'}',
        (tester) async {
      final capture = FakeCapture()
        ..failure = const CaptureFailure('attendance.location_off',
            recovery: CaptureRecovery.locationSettings);
      final posts = <String>[];
      final container = await pumpApp(tester,
          savedSession: true,
          locale: Locale(checkOut ? 'ar' : 'en'),
          attendanceRecords: checkOut ? [recordJson()] : [],
          capture: capture, onRequest: (request) {
        if (request.method == 'POST') posts.add(request.path);
      });
      if (checkOut) {
        container.read(appRouterProvider).goNamed('attendance');
        await tester.pumpAndSettle();
      }
      final label =
          (checkOut ? 'attendance.check_out' : 'attendance.check_in').tr();
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final toast = find.byType(ToastCard);
      expect(toast, findsOneWidget);
      expect(
          find.descendant(
              of: toast, matching: find.text('attendance.location_off'.tr())),
          findsOneWidget);
      final contentTop = tester.getTopLeft(find.byType(Navigator).first).dy;
      expect(tester.getTopLeft(toast).dy - contentTop, lessThan(100));
      expect(find.text('attendance.open_settings'.tr()), findsOneWidget);
      expect(capture.calls, 1);
      expect(posts, isEmpty);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(ToastCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Home older open record blocks capture and routes forgotten checkout with owned id',
      (tester) async {
    await pumpApp(tester,
        savedSession: true,
        attendanceRecords: [recordJson(date: '2026-10-04')]);
    expect(
        find.textContaining(
            'An attendance record from 2026-10-04 is still open'),
        findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    expect(find.byIcon(Icons.edit_calendar_rounded), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final request = find.text('Forgotten check-out');
    await tester.ensureVisible(request);
    await tester.tap(request);
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-04'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('returning to Home does not reload attendance', (tester) async {
    var loads = 0;
    final container = await pumpApp(tester,
        savedSession: true,
        attendanceRecords: [recordJson()], onRequest: (request) {
      if (request.path == '/attendance/me') loads++;
    });
    final initialLoads = loads;
    expect(initialLoads, greaterThan(0));
    container.read(appRouterProvider).goNamed('account');
    await tester.pumpAndSettle();
    container.read(appRouterProvider).goNamed('home');
    await tester.pumpAndSettle();
    expect(loads, initialLoads);
    expect(find.byType(AttendanceWorkProgress), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
  });
  testWidgets(
      'Home failure disables capture; refresh and foreground update returned record',
      (tester) async {
    var offline = true;
    final records = <Map<String, dynamic>>[];
    await pumpApp(tester,
        savedSession: true,
        attendanceRecords: records,
        attendanceUnavailable: () => offline);
    expect(find.text('The service is unavailable. Please try again.'),
        findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    offline = false;
    expect(find.text('Refresh'), findsNothing);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Check in'), findsOneWidget);
    records.add(recordJson());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Check out'), findsOneWidget);
  });
  testWidgets('Arabic dark Home summary supports large text landscape',
      (tester) async {
    final container = await pumpApp(tester,
        savedSession: true,
        locale: const Locale('ar'),
        attendanceRecords: [recordJson()]);
    await container.read(themeModeProvider.notifier).setDark(true);
    tester.view.physicalSize = const Size(844, 390);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('2026-10-05'), findsOneWidget);
    expect(find.textContaining('EMP-000001'), findsOneWidget);
    expect(find.textContaining('تاريخ الشركة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'attendance uses server workday and closed workdays cannot repeat check-in',
      (tester) async {
    final container = await pumpApp(tester, savedSession: true);
    container.read(appRouterProvider).goNamed('attendance');
    await tester.pumpAndSettle();
    expect(find.text('Current workday'), findsOneWidget);
    expect(find.text('2026-10-05'), findsNWidgets(2));
    expect(find.text('Africa/Cairo'), findsNWidgets(2));
    expect(find.textContaining('This workday is complete'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Arabic dark account without employee supports large text and logout',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await pumpApp(tester,
        savedSession: true, noEmployee: true, locale: const Locale('ar'));
    expect(find.textContaining('حسابك غير مرتبط'), findsOneWidget);
    await tester.tap(find.text('الحساب'));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.text('الحساب').first)),
        TextDirection.rtl);
    await tester.ensureVisible(find.text('تسجيل الخروج'));
    await tester.tap(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(container.read(sessionProvider), isA<SessionUnauthenticated>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('attendance evidence and status filtering remain accessible',
      (tester) async {
    final container = await pumpApp(tester, savedSession: true);
    container.read(appRouterProvider).goNamed('attendance');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View evidence'));
    await tester.tap(find.text('View evidence'));
    await tester.pumpAndSettle();
    expect(find.text('No evidence available.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All statuses'));
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Late').last);
    await tester.pumpAndSettle();
    expect(find.text('No records match. Clear or adjust the filters.'),
        findsOneWidget);
    expect(find.text('View evidence'), findsNothing);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('View evidence'), findsOneWidget);
  });

  testWidgets(
      'request history filters and separates manager from final HR decision',
      (tester) async {
    final container = await pumpApp(tester, savedSession: true, requests: [
      {
        ...requestJson(),
        'managerStage': 'rejected',
        'managerReview': {
          'status': 'rejected',
          'reviewedBy': 'Department manager',
          'reviewedAt': '2026-10-06T10:01:00Z',
          'reason': 'No department coverage'
        }
      }
    ]);
    container.read(appRouterProvider).goNamed('requests');
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);
    await tester.ensureVisible(find.text('Request details').first);
    await tester.tap(find.text('Request details').first);
    await tester.pumpAndSettle();
    expect(find.text('Recommended rejection'), findsOneWidget);
    expect(find.text('No final reviewer recorded'), findsOneWidget);
    final reason = find.byType(AppTextArea);
    await tester.ensureVisible(reason);
    await tester.enterText(
        find.descendant(of: reason, matching: find.byType(TextField)),
        'No longer needed');
    await tester.ensureVisible(find.text('Withdraw request'));
    await tester.tap(find.text('Withdraw request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw request').last);
    await tester.pumpAndSettle();
    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.byType(AppTextArea), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Excuse form accepts an optional reason and submits using assigned shift',
      (tester) async {
    var notificationLoads = 0;
    final container =
        await pumpApp(tester, savedSession: true, onRequest: (request) {
      if (request.path == '/notifications') notificationLoads++;
    });
    container.read(appRouterProvider).goNamed('newRequest');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Excuse'));
    await tester.tap(find.text('Excuse').last);
    await tester.pumpAndSettle();
    expect(
        find.text('Reason (optional, up to 120 characters)'), findsOneWidget);
    for (var index = 0; index < 2; index++) {
      final date = find.text('Choose a date').first;
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '10/05/2026');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Submit request'));
    final beforeSubmit = notificationLoads;
    await tester.tap(find.text('Submit request'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
        find.descendant(
            of: find.byType(ToastCard),
            matching: find.text('Request saved by the server.')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NewRequestScreen), findsNothing);
    expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/requests');
    expect(notificationLoads, greaterThan(beforeSubmit));
    expect(container.read(requestsProvider).items.single.type, 'excuse');
    expect(container.read(requestsProvider).items.single.reason, '');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic dark request history and form render on a small phone',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final container =
        await pumpApp(tester, savedSession: true, locale: const Locale('ar'));
    container.read(appRouterProvider).goNamed('requests');
    await tester.pumpAndSettle();
    expect(
        find.text('لا توجد طلبات بعد. يمكنك إنشاء طلب جديد.'), findsOneWidget);
    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.text('نوع الطلب'))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload card adds files, explains the limit and allows removal',
      (tester) async {
    final picker = _AttachmentPicker();
    final container =
        await pumpApp(tester, savedSession: true, attachmentPicker: picker);
    container.read(appRouterProvider).goNamed('newRequest');
    await tester.pumpAndSettle();
    for (var index = 1; index <= 3; index++) {
      final upload = find.text('Add attachment');
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await tester.pumpAndSettle();
      expect(find.text('document-$index.pdf'), findsOneWidget);
    }
    final limit = find.text('Choose at most 3 attachments.');
    await tester.ensureVisible(limit);
    await tester.tap(limit);
    await tester.pumpAndSettle();
    expect(picker.picks, 3);
    final remove = find.byTooltip('Remove attachment').first;
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('document-1.pdf'), findsNothing);
    expect(find.text('Add attachment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request type card opens the matching form', (tester) async {
    final container = await pumpApp(tester, savedSession: true);
    container.read(appRouterProvider).goNamed('requests');
    await tester.pumpAndSettle();
    final sick = find.text('requests.types.sick'.tr());
    await tester.ensureVisible(sick);
    await tester.tap(sick);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RequestTypeCards>(find.byType(RequestTypeCards))
            .selectedType,
        'sick');
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    final cards = find.descendant(
        of: find.byType(RequestTypeCards), matching: find.byType(AppCard));
    final size = tester.getSize(cards.first);
    for (final card in cards.evaluate()) {
      expect(tester.getSize(find.byWidget(card.widget)), size);
    }
    expect(tester.takeException(), isNull);
  });

  for (final arabic in [false, true]) {
    testWidgets(
        'request cards support large text and card navigation ${arabic ? 'Arabic dark' : 'English'}',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await pumpApp(tester,
          savedSession: true,
          locale: Locale(arabic ? 'ar' : 'en'),
          requests: [
            {
              ...requestJson(),
              'type': 'sick',
              'reason':
                  'A long request reason that remains readable without pushing the status out of the card.'
            },
            requestJson(id: 'request-b', status: 'approved'),
            requestJson(id: 'request-c', status: 'rejected'),
            requestJson(id: 'request-d', status: 'withdrawn'),
          ]);
      if (arabic) {
        await container.read(themeModeProvider.notifier).setDark(true);
      }
      container.read(appRouterProvider).goNamed('requests');
      await tester.pumpAndSettle();
      final typeCards = find.descendant(
          of: find.byType(RequestTypeCards), matching: find.byType(AppCard));
      final cardSize = tester.getSize(typeCards.first);
      for (final card in typeCards.evaluate()) {
        expect(tester.getSize(find.byWidget(card.widget)), cardSize);
      }
      for (final icon in [
        Icons.schedule_rounded,
        Icons.check_circle_outline_rounded,
        Icons.cancel_outlined,
        Icons.remove_circle_outline_rounded
      ]) {
        await tester.ensureVisible(find.byIcon(icon));
        expect(tester.takeException(), isNull);
      }
      final type = find.text('requests.types.sick'.tr()).last;
      await tester.ensureVisible(type);
      await tester.tap(type);
      await tester.pumpAndSettle();
      expect(find.byType(RequestDetailsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final route in ['home', 'requests', 'account', 'sales']) {
    testWidgets(
        '$route refresh keeps content; only pulling shows refresh animation',
        (tester) async {
      Completer<void>? gate;
      final container = await pumpApp(tester,
          savedSession: true,
          salesSubmit: true,
          salesActivities: [salesJson()],
          requests: [requestJson()], beforeRequest: (_) async {
        await gate?.future;
      });
      container.read(appRouterProvider).goNamed(route);
      await tester.pumpAndSettle();
      Object currentState() => switch (route) {
            'home' => container.read(attendanceProvider),
            'requests' => container.read(requestsProvider),
            'sales' => container.read(salesListProvider(false)),
            _ => container.read(sessionProvider),
          };
      final previous = currentState();
      final cardCount = find.byType(AppCard).evaluate().length;
      expect(cardCount, greaterThan(0));
      gate = Completer<void>();
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.byType(AppCard).evaluate().length, cardCount);
      expect(currentState(), same(previous));
      gate.complete();
      await tester.pumpAndSettle();
      expect(currentState(), same(previous));
      gate = Completer<void>();
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, 450));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(find.byType(AppCard).evaluate().length, cardCount);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(currentState(), same(previous));
      expect(tester.takeException(), isNull);
    });
  }
  for (final route in ['account', 'sales', 'attendance']) {
    testWidgets('$route uses pull-to-refresh without a refresh button',
        (tester) async {
      var loads = 0;
      final container = await pumpApp(tester,
          savedSession: true, salesSubmit: true, onRequest: (request) {
        if (route == 'account' && request.path == '/auth/me' ||
            route == 'sales' && request.path == '/sales/access' ||
            route == 'attendance' && request.path == '/attendance/me') {
          loads++;
        }
      });
      container.read(appRouterProvider).goNamed(route);
      await tester.pumpAndSettle();
      final before = loads;
      expect(before, greaterThan(0));
      expect(find.text('$route.refresh'.tr()), findsNothing);
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(loads, greaterThan(before));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty notifications show a bell and refresh by pulling',
      (tester) async {
    var loads = 0;
    final container =
        await pumpApp(tester, savedSession: true, onRequest: (request) {
      if (request.path == '/notifications') loads++;
    });
    container.read(appRouterProvider).goNamed('notifications');
    await tester.pumpAndSettle();
    expect(find.text('You have no notifications yet.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsWidgets);
    expect(find.text('Refresh'), findsNothing);
    final before = loads;
    await tester.drag(find.byType(ListView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(loads, greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new request omits the guidelines section', (tester) async {
    final container = await pumpApp(tester, savedSession: true);
    container.read(appRouterProvider).goNamed('newRequest');
    await tester.pumpAndSettle();
    expect(find.text('New request'), findsOneWidget);
    expect(find.text('requests.form_intro'.tr()), findsNothing);
    expect(find.text('requests.guidelines'.tr()), findsNothing);
    expect(find.text('requests.range_hint'.tr()), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request form refreshes by pulling without clearing entered text',
      (tester) async {
    var loads = 0;
    final container =
        await pumpApp(tester, savedSession: true, onRequest: (request) {
      if (request.path == '/requests/me') loads++;
    });
    container.read(appRouterProvider).goNamed('newRequest');
    await tester.pumpAndSettle();
    final reason = find.byType(AppTextArea);
    await tester.ensureVisible(reason);
    await tester.enterText(
        find.descendant(of: reason, matching: find.byType(TextField)),
        'Personal appointment');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final before = loads;
    expect(find.text('requests.refresh'.tr()), findsNothing);
    expect(find.text('requests.reconcile'.tr()), findsNothing);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(loads, greaterThan(before));
    expect(find.text('Personal appointment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Requests refreshes by dragging down, including an empty list',
      (tester) async {
    var loads = 0;
    final container =
        await pumpApp(tester, savedSession: true, onRequest: (request) {
      if (request.path == '/requests/me') loads++;
    });
    container.read(appRouterProvider).goNamed('requests');
    await tester.pumpAndSettle();
    final before = loads;
    expect(find.text('Refresh'), findsNothing);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(loads, greaterThan(before));
    expect(find.text('No requests yet. Create a request to get started.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('request screens support large text in phone landscape',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await pumpApp(tester, savedSession: true);
    tester.view.physicalSize = const Size(812, 375);
    container.read(appRouterProvider).goNamed('requests');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    container.read(appRouterProvider).goNamed('newRequest');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit request'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('private attachment preview disappears on sign-out',
      (tester) async {
    final png = image.encodePng(image.Image(width: 10, height: 10));
    final container = await pumpApp(tester, savedSession: true, requests: [
      {
        ...requestJson(),
        'attachments': [
          {
            'name': 'private-note.png',
            'mimeType': 'image/png',
            'content': base64Encode(png)
          }
        ]
      }
    ]);
    container
        .read(appRouterProvider)
        .goNamed('requestDetails', pathParameters: {'id': 'request-a'});
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Preview'));
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    container.read(authRepositoryProvider).logout();
    await tester.pumpAndSettle();
    expect(find.text('private-note.png'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(container.read(requestsProvider).items, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
