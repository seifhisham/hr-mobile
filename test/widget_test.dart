import 'dart:io';
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
import 'package:hrmobile/src/ui/requests/department_reviews_screen.dart';
import 'package:hrmobile/src/shared/widgets/ui/app/actions/app_button.dart';
import 'package:hrmobile/src/data/repositories/auth_repository_impl.dart';
import 'package:hrmobile/src/services/auth_service.dart';
import 'package:hrmobile/src/ui/auth/providers/session_provider.dart';
import 'package:hrmobile/src/routing/app_router.dart';
import 'package:hrmobile/src/services/attendance_service.dart';
import 'package:hrmobile/src/ui/attendance/attendance_provider.dart';
import 'attendance_test.dart' show policyJson, recordJson;
import 'requests_test.dart' show requestJson;
import 'notifications_test.dart' show notificationJson;
import 'package:hrmobile/src/services/requests_service.dart';
import 'package:hrmobile/src/ui/requests/requests_provider.dart';
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

void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester,
      {bool savedSession = false,
      bool noEmployee = false,
      bool offline = false,
      Locale locale = const Locale('en'),
      List<Map<String, dynamic>> requests = const [],
      List<Map<String, dynamic>> notifications = const [],
      List<Map<String, dynamic>> managedRequests = const [],
      bool removeNotificationOnRead = false,
      void Function(RequestOptions)? onRequest}) async {
    final requestItems = List<Map<String, dynamic>>.of(requests);
    final notificationItems = List<Map<String, dynamic>>.of(notifications);
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
    client.httpClientAdapter = TestAdapter((request) {
      onRequest?.call(request);
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
      if (request.path == '/attendance/me') {
        return jsonResponse({
          'workDate': '2026-10-05',
          'schedule': schedules.first,
          'records': [recordJson(closed: true)]
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

  testWidgets('manager alerts open only server-authorized department requests',
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
    expect(find.byType(DepartmentReviewsScreen), findsOneWidget);
    expect(find.text('Department Colleague'), findsOneWidget);
    await tester.tap(find.text('Request details'));
    await tester.pumpAndSettle();
    expect(find.text('Department Colleague'), findsOneWidget);
    expect(find.text('Withdraw request'), findsNothing);
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

  testWidgets('redesigned workspace navigation and visual previews',
      (tester) async {
    const previews = bool.fromEnvironment('DESIGN_PREVIEWS');
    const previewArabic = bool.fromEnvironment('DESIGN_ARABIC');
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
        locale: previewArabic ? const Locale('ar') : const Locale('en'),
        notifications: previews ? [notificationJson()] : []);
    for (final route in [
      'home',
      'attendance',
      'requests',
      'account',
      'notifications',
      'newRequest',
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

  testWidgets(
      'attendance uses server workday and closed workdays cannot repeat check-in',
      (tester) async {
    final container = await pumpApp(tester, savedSession: true);
    container.read(appRouterProvider).goNamed('attendance');
    await tester.pumpAndSettle();
    expect(find.text('Current workday'), findsOneWidget);
    expect(find.text('2026-10-05'), findsNWidgets(2));
    expect(find.text('Africa/Cairo'), findsOneWidget);
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
    expect(Directionality.of(tester.element(find.text('الحساب'))),
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
    await tester.tap(find.text('Normal vacation'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.text('Request saved by the server.'), findsOneWidget);
    expect(notificationLoads, greaterThan(beforeSubmit));
    expect(container.read(requestsProvider).items.single.type, 'excuse');
    expect(container.read(requestsProvider).items.single.reason, '');
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
