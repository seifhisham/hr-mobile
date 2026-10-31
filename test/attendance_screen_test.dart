import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/core/i18n/locale_keys.g.dart';
import 'package:hodour/src/imports/imports.dart';
import 'package:hodour/src/ui/attendance/attendance_provider.dart';
import 'package:hodour/src/ui/attendance/attendance_screen.dart';
import 'attendance_test.dart'
    show FakeRepository, FakeCapture, snapshot, recordJson;

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets(
        'Check-In retries a failed load and opens history filters in $language',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            name: 'attendance',
            builder: (context, state) => const AttendanceScreen()),
      ]);
      addTearDown(router.dispose);
      final capture = FakeCapture();
      final repository = FakeRepository([
        left(const NetworkFailure('Offline')),
        right(snapshot(records: [recordJson(closed: true)])),
      ]);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        startLocale: Locale(language),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const CodegenLoader(),
        child: ProviderScope(
            overrides: [
              attendanceProvider.overrideWith((ref) =>
                  AttendanceController(repository, capture, enabled: false)),
              attendanceCaptureProvider.overrideWithValue(capture),
            ],
            child: ScreenUtilInit(
                designSize: const Size(390, 844),
                builder: (context, _) => MaterialApp.router(
                      theme: language == 'ar'
                          ? buildDarkTheme(primaryColorHex: '#2457A7')
                          : buildLightTheme(primaryColorHex: '#2457A7'),
                      locale: context.locale,
                      supportedLocales: context.supportedLocales,
                      localizationsDelegates: context.localizationDelegates,
                      builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler: const TextScaler.linear(1.5)),
                          child: child!),
                      routerConfig: router,
                    ))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(find.text('attendance.refresh'.tr()));
      await tester.pumpAndSettle();
      expect(find.text('attendance.checked_out'.tr()), findsOneWidget);
      expect(repository.posts, 0);
      final filters = find.text('attendance.filters'.tr());
      await tester.ensureVisible(filters);
      await tester.tap(filters);
      await tester.pumpAndSettle();
      final clear = find.text('attendance.clear_filters'.tr());
      await tester.ensureVisible(clear);
      expect(clear.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
