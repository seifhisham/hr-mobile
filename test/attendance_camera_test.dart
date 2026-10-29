import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hodour/src/data/models/user_model.dart';
import 'package:hodour/src/data/repositories/auth_repository.dart';
import 'package:hodour/src/shared/widgets/attendance_camera_dialog.dart';
import 'package:hodour/src/shared/widgets/ui/app/actions/app_button.dart';
import 'package:hodour/src/theme/theme.dart';
import 'package:hodour/src/ui/auth/providers/session_provider.dart';
import 'package:hodour/src/utils/utils.dart';
import 'auth_session_test.dart' show profile;

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, Map<String, dynamic>> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      values[locale.languageCode]!;
}

class _Auth extends AuthRepository {
  final changes = StreamController<AppUser?>.broadcast();
  final user = AppUser.fromJson(profile);
  @override
  Stream<AppUser?> get onAuthStateChanged => changes.stream;
  @override
  FutureEither<AppUser?> checkAuthState() async => right(user);
  @override
  FutureEither<AppUser> login(
          {required String workspace,
          required String email,
          required String password}) async =>
      right(user);
  @override
  FutureEither<void> logout() async {
    changes.add(null);
    return right(null);
  }

  @override
  FutureEither<void> changePassword(
          {required String currentPassword,
          required String newPassword}) async =>
      right(null);
}

class _Camera extends CameraController {
  _Camera()
      : super(
            const CameraDescription(
                name: 'test rear camera',
                lensDirection: CameraLensDirection.back,
                sensorOrientation: 90),
            ResolutionPreset.high,
            enableAudio: false);
  Object? initializationError;
  Completer<void>? initializeWait;
  Completer<XFile>? photoWait;
  XFile? photo;
  int shots = 0;
  bool released = false;
  @override
  Future<void> initialize() async {
    await initializeWait?.future;
    if (initializationError case final error?) throw error;
    if (!released) {
      value = value.copyWith(
          isInitialized: true, previewSize: const Size(1280, 720));
    }
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.blue);
  @override
  Future<XFile> takePicture() async {
    shots++;
    return photoWait == null ? photo! : photoWait!.future;
  }

  @override
  Future<void> dispose() async {
    released = true;
    await super.dispose();
  }
}

void main() {
  late _Camera camera;
  late _Auth auth;
  late Directory directory;
  Object? returned;
  setUp(() async {
    camera = _Camera();
    auth = _Auth();
    directory = await Directory.systemTemp.createTemp('attendance-modal-test-');
    returned = null;
  });
  tearDown(() async {
    await auth.changes.close();
    await directory.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester,
      {bool rtl = false, bool dark = false, double scale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final translations = (await tester.runAsync(() async => {
          for (final language in ['en', 'ar'])
            language: jsonDecode(
                await File('assets/translations/$language.json')
                    .readAsString()) as Map<String, dynamic>,
        }))!;
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ar')],
          startLocale: Locale(rtl ? 'ar' : 'en'),
          saveLocale: false,
          path: 'test',
          assetLoader: _Translations(translations),
          child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (context, _) => MaterialApp(
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    localizationsDelegates: context.localizationDelegates,
                    theme: dark
                        ? buildDarkTheme(primaryColorHex: '#2457A7')
                        : buildLightTheme(primaryColorHex: '#2457A7'),
                    home: Builder(
                        builder: (context) => Scaffold(
                            body: TextButton(
                                onPressed: () async {
                                  returned = await showDialog<Object>(
                                      context: context,
                                      builder: (_) => MediaQuery(
                                          data: MediaQuery.of(context).copyWith(
                                              textScaler:
                                                  TextScaler.linear(scale)),
                                          child: Directionality(
                                              textDirection: rtl
                                                  ? TextDirection.rtl
                                                  : TextDirection.ltr,
                                              child: AttendanceCameraDialog(
                                                  createController: () async =>
                                                      camera))));
                                },
                                child: const Text('Open camera')))),
                  ))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
  }

  testWidgets('camera stays in a modal and returns one fresh photo',
      (tester) async {
    final file = (await tester.runAsync(
        () => File('${directory.path}/camera.jpg').writeAsBytes([1, 2, 3])))!;
    camera.photo = XFile(file.path);
    await open(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.byType(Scrollable)),
        findsNothing);
    expect(tester.getSize(find.byType(CameraPreview)).height, greaterThan(0));
    expect(camera.enableAudio, false);
    await tester.tap(find.byType(AppButton).first);
    await tester.pumpAndSettle();
    expect(returned, same(camera.photo));
    expect(camera.shots, 1);
    expect(camera.released, true);
    expect(await tester.runAsync(file.exists), true,
        reason: 'Ownership passes to capture service cleanup.');
  });
  testWidgets('cancel releases camera without taking a photo', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cancel-attendance-camera')));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    expect(camera.shots, 0);
    expect(camera.released, true);
  });
  testWidgets(
      'closing during capture deletes late results and blocks duplicate taps',
      (tester) async {
    camera.photoWait = Completer<XFile>();
    await open(tester);
    await tester.tap(find.byType(AppButton).first);
    await tester.pump();
    expect(
        tester.widget<AppButton>(find.byType(AppButton).first).isLoading, true);
    await tester.tap(find.byType(AppButton).first);
    await tester.tap(find.byKey(const ValueKey('cancel-attendance-camera')));
    await tester.pumpAndSettle();
    final file = (await tester.runAsync(
        () => File('${directory.path}/late.jpg').writeAsBytes([1, 2, 3])))!;
    camera.photoWait!.complete(XFile(file.path));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(camera.shots, 1);
    expect(returned, isNull);
    expect(await tester.runAsync(file.exists), false);
    expect(camera.released, true);
  });
  testWidgets('outside dismissal deletes a capture arriving during close',
      (tester) async {
    camera.photoWait = Completer<XFile>();
    await open(tester);
    await tester.tap(find.byType(AppButton).first);
    await tester.pump();
    await tester.tapAt(const Offset(1, 1));
    await tester.pump();
    final file = (await tester.runAsync(() =>
        File('${directory.path}/dismissed.jpg').writeAsBytes([1, 2, 3])))!;
    camera.photoWait!.complete(XFile(file.path));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    expect(find.text('Open camera'), findsOneWidget);
    expect(await tester.runAsync(file.exists), false);
    expect(camera.released, true);
  });
  testWidgets('denied permission returns existing settings recovery failure',
      (tester) async {
    camera.initializationError = CameraException('CameraAccessDenied', '');
    await open(tester);
    expect(returned, isA<CaptureFailure>());
    expect((returned as CaptureFailure).recovery, CaptureRecovery.appSettings);
    expect(camera.released, true);
  });
  testWidgets('backgrounding cancels the modal and releases camera',
      (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(returned, isNull);
    expect(camera.released, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });
  testWidgets('sign-out closes camera without capture', (tester) async {
    await open(tester);
    auth.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceCameraDialog), findsNothing);
    expect(camera.released, true);
    expect(camera.shots, 0);
  });
  testWidgets('dark RTL modal fits small landscape with large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, rtl: true, dark: true, scale: 2);
    expect(find.text('صورة الحضور'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.byType(Scrollable)),
        findsNothing);
    expect(tester.getSize(find.byType(CameraPreview)).height, greaterThan(0));
    final close = find.byKey(const ValueKey('cancel-attendance-camera'));
    expect(tester.getCenter(close).dx,
        greaterThan(tester.getCenter(find.byType(Dialog)).dx),
        reason: 'Close remains at the top right in Arabic');
    expect(tester.getRect(close).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CameraPreview)).top));

    expect(find.byKey(const ValueKey('cancel-attendance-camera')).hitTestable(),
        findsOneWidget,
        reason: 'Cancel stays visible without scrolling');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('cancel-attendance-camera')));
    await tester.pumpAndSettle();
    expect(camera.released, true);
  });
}
