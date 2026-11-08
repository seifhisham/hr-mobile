import 'dart:async';
import 'dart:ui' as ui;
import 'src/imports/core_imports.dart';
import 'src/imports/packages_imports.dart';
import 'src/app.dart';
import 'src/services/push_notification_service.dart';
import 'src/services/crash_reporting_service.dart';

Future<void> main() async {
  await runZonedGuarded(_bootstrap, (error, stackTrace) {
    unawaited(CrashReportingService.instance.recordError(error, stackTrace));
    AppLogger.error(
      'Unhandled asynchronous error',
      error: error,
      stackTrace: stackTrace,
      category: LogCategory.app,
    );
  });
}

Future<void> _bootstrap() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  FlutterError.onError = (details) {
    unawaited(CrashReportingService.instance
        .recordError(details.exception, details.stack ?? StackTrace.current));
    AppLogger.error(
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
      category: LogCategory.app,
      context: {'library': details.library ?? 'unknown'},
    );
    FlutterError.presentError(details);
  };

  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(CrashReportingService.instance.recordError(error, stackTrace));
    AppLogger.error(
      'Unhandled platform error',
      error: error,
      stackTrace: stackTrace,
      category: LogCategory.app,
    );
    return CrashReportingService.instance.enabled;
  };

  AppLogger.info('Application bootstrap started', category: LogCategory.app);

  await EasyLocalization.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);

  await CrashReportingService.instance.initialize();

  await AppConfig.init();
  AuthService.instance.initialize();
  AppLogger.success(
    'Application configuration initialized',
    category: LogCategory.backend,
  );

  runApp(
    const LocalizationWrapper(
      child: StateWrapper(
        child: App(),
      ),
    ),
  );

  AppLogger.success('Application started', category: LogCategory.app);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(PushNotificationService.instance.start());
  });
}
