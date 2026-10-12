import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hrmobile/src/imports/imports.dart';
import 'package:hrmobile/src/services/attendance_location_warning.dart';
import 'package:hrmobile/src/ui/attendance/attendance_monitor_provider.dart';
import 'package:hrmobile/src/ui/attendance/attendance_monitoring.dart';
import 'package:hrmobile/src/ui/attendance/attendance_provider.dart';
import 'package:hrmobile/src/data/models/attendance_location.dart';
import 'attendance_location_test.dart'
    show LocationSource, LocationApi, monitored;
import 'attendance_test.dart' show FakeCapture, FakeRepository;

class DisplayMonitor extends AttendanceMonitor {
  DisplayMonitor(AttendanceMonitorState initial)
      : super(LocationSource(), LocationApi(), reconcile: () async {}) {
    state = initial;
  }
  set display(AttendanceMonitorState value) => state = value;
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
                attendanceProvider.overrideWith((ref) => controller),
              ],
              child: ScreenUtilInit(
                  designSize: const Size(390, 844),
                  builder: (context, _) => MaterialApp(
                      theme: language == 'ar'
                          ? ThemeData.dark()
                          : ThemeData.light(),
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
      monitor.display = const AttendanceMonitorState();
      await tester.pump();
      expect(find.text('Employee screen'), findsOneWidget);
      expect(
          find.textContaining(language == 'en'
              ? 'Attendance remains open'
              : 'يظل سجل الحضور مفتوحًا'),
          findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
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
