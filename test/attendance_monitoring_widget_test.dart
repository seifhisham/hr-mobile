import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hodour/src/imports/imports.dart';
import 'package:hodour/src/services/attendance_location_warning.dart';
import 'package:hodour/src/ui/attendance/attendance_monitor_provider.dart';
import 'package:hodour/src/ui/attendance/attendance_monitoring.dart';
import 'package:hodour/src/ui/attendance/attendance_provider.dart';
import 'package:hodour/src/data/models/attendance_location.dart';
import 'attendance_location_test.dart'
    show LocationSource, LocationApi, monitored;
import 'attendance_test.dart' show FakeCapture, FakeRepository;

class DisplayMonitor extends AttendanceMonitor {
  DisplayMonitor(AttendanceMonitorState initial)
      : super(LocationSource(), LocationApi(), reconcile: () async {}) {
    state = initial;
  }
  Completer<void>? enableGate;
  Object? enableError;
  @override
  Future<void> enable() async {
    await enableGate?.future;
    if (enableError case final error?) throw error;
    state = AttendanceMonitorState(
        record: state.record,
        policy: state.policy,
        location: const AttendanceLocation(status: 'inside'));
  }

  set display(AttendanceMonitorState value) => state = value;
}

class SetupSource extends LocationSource {
  bool backgroundAllowed = true;
  @override
  Future<bool> hasBackgroundAccess() async => backgroundAllowed;
}

class SetupWarning extends AttendanceLocationWarning {
  bool allowed = true;
  @override
  Future<void> update(DateTime? deadline,
      {String? title, String? message}) async {}
  @override
  Future<bool> requestPermission() async => allowed;
}

class Translations extends AssetLoader {
  const Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets(
        'monitor warning, recovery and layout in $language with large text',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final source = SetupSource();
      final warning = SetupWarning();
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      late Map<String, dynamic> translations;
      await tester.runAsync(() async {
        translations = jsonDecode(await rootBundle.loadString(
            'assets/translations/$language.json')) as Map<String, dynamic>;
      });
      final snapshot = monitored();
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      final monitor = DisplayMonitor(AttendanceMonitorState(
          record: snapshot.open,
          policy: snapshot.policy.tracking,
          location: AttendanceLocation(status: 'outside', returnBy: deadline)));
      final repository = FakeRepository([right(snapshot)]);
      final controller =
          AttendanceController(repository, FakeCapture(), enabled: false);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ar')],
          startLocale: Locale(language),
          path: 'assets/translations',
          saveLocale: false,
          assetLoader: Translations(translations),
          child: ProviderScope(
              overrides: [
                attendanceMonitorProvider.overrideWith((ref) => monitor),
                attendanceLocationSourceProvider.overrideWithValue(source),
                attendanceLocationWarningProvider.overrideWithValue(warning),
                attendanceProvider.overrideWith((ref) => controller),
              ],
              child: ScreenUtilInit(
                  designSize: const Size(390, 844),
                  builder: (context, _) => MaterialApp(
                      navigatorKey: rootNavigatorKey,
                      theme: language == 'ar'
                          ? buildDarkTheme(primaryColorHex: '#2457A7')
                          : buildLightTheme(primaryColorHex: '#2457A7'),
                      locale: context.locale,
                      supportedLocales: context.supportedLocales,
                      localizationsDelegates: context.localizationDelegates,
                      builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler: const TextScaler.linear(1.8)),
                          child: AttendanceMonitoring(child: child!)),
                      home: const Scaffold(body: Text('Employee screen')))))));
      await tester.pump();
      await tester.pump();
      expect(
          find.textContaining(language == 'en'
              ? 'You are outside the office'
              : 'أنت خارج المكتب'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(repository.responses, isEmpty,
          reason: 'Expiry refreshes attendance');
      expect(monitor.state.record!.checkOut, isNull,
          reason: 'No local checkout');
      monitor.display = AttendanceMonitorState(
          record: snapshot.open,
          policy: snapshot.policy.tracking,
          location: const AttendanceLocation(status: 'unavailable'));
      await tester.pump();
      expect(
          find.textContaining(language == 'en'
              ? 'Attendance remains open'
              : 'يظل سجل الحضور مفتوحًا'),
          findsOneWidget);
      expect(
          find.textContaining(language == 'en'
              ? 'You are outside the office'
              : 'أنت خارج المكتب'),
          findsNothing);
      monitor.display = AttendanceMonitorState(
          record: snapshot.open,
          policy: snapshot.policy.tracking,
          location: const AttendanceLocation(status: 'inside'));
      await tester.pump();
      expect(find.byType(AppExpansionPanel), findsNothing);
      await tester.ensureVisible(find.text('tracking.details'.tr()));
      final card = find
          .ancestor(
              of: find.text('tracking.details'.tr()),
              matching: find.byType(AppCard))
          .first;
      await tester.ensureVisible(card);
      final openDetails = tester.widget<AppCard>(card).onTap!;
      openDetails();
      openDetails();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.getRect(find.byType(BottomSheet)).top,
          greaterThanOrEqualTo(tester.getRect(card).bottom),
          reason: 'The sheet stays below the monitoring card');
      await tester.tapAt(tester.getCenter(card));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byTooltip('requests.close'.tr()));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      monitor.display = AttendanceMonitorState(
          record: snapshot.open,
          policy: snapshot.policy.tracking,
          failure: const CaptureFailure('attendance.location_blocked'));
      await tester.pump();
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('attendance.location_blocked'.tr())),
          findsOneWidget,
          reason: 'Permission errors must be visible inside the open sheet');
      monitor.enableGate = Completer<void>();
      final enable = find.text('tracking.enable'.tr());
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pump();
      expect(find.text('tracking.enabling'.tr()), findsOneWidget);
      monitor.enableGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('tracking.background_enabled'.tr()), findsOneWidget);
      expect(find.text('tracking.notifications_enabled'.tr()), findsOneWidget);
      expect(find.text('tracking.enabling'.tr()), findsNothing);
      source.backgroundAllowed = false;
      warning.allowed = false;
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(find.text('tracking.background_needed'.tr()), findsOneWidget);
      expect(find.text('tracking.notifications_denied'.tr()), findsOneWidget);
      expect(find.text('tracking.background_enabled'.tr()), findsNothing);
      monitor.enableError = const CaptureFailure('attendance.location_blocked');
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('attendance.location_blocked'.tr())),
          findsOneWidget);
      expect(find.text('tracking.enabling'.tr()), findsNothing);
      expect(find.text('tracking.privacy_title'.tr()), findsOneWidget);
      expect(find.text('tracking.updates_title'.tr()), findsOneWidget);
      expect(find.text('tracking.return_title'.tr()), findsOneWidget);
      expect(find.text('tracking.permissions_title'.tr()), findsOneWidget);
      expect(tester.takeException(), isNull);
      monitor.display = const AttendanceMonitorState();
      await tester.pump();
      expect(find.text('tracking.stopped'.tr()), findsOneWidget);
      expect(find.text('tracking.enable'.tr()), findsNothing);
      await tester.tap(find.byTooltip('requests.close'.tr()));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Employee screen'), findsOneWidget);
      expect(
          find.textContaining(language == 'en'
              ? 'Attendance remains open'
              : 'يظل سجل الحضور مفتوحًا'),
          findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('late notification show cannot outlive cancellation',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return call.method == 'initialize' ? true : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final warning = AttendanceLocationWarning();
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    final pending = warning.update(deadline,
        title: 'Return', message: 'Return before the deadline');
    final cancelled = warning.update(null);
    await tester.pump();
    await tester.pump();
    await pending;
    await cancelled;
    expect(calls.where((call) => call.method == 'show'), isEmpty);
    expect(calls.where((call) => call.method == 'cancel').length, 1);
    final shown = warning.update(deadline,
        title: 'Return', message: 'Return before the deadline');
    await tester.pump();
    await shown;
    final stopped = warning.update(null);
    await tester.pump();
    await stopped;
    expect(calls.map((call) => call.method).toList().sublist(1),
        ['cancel', 'show', 'cancel']);
    debugDefaultTargetPlatformOverride = null;
  });
}
