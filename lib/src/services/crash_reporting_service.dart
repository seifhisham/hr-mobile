import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';
import '../utils/utils.dart';

class CrashReportingService {
  CrashReportingService({FirebaseCrashlytics? crashlytics})
      : _crashlytics = crashlytics;
  static final instance = CrashReportingService();
  FirebaseCrashlytics? _crashlytics;
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> initialize({bool enabled = !kDebugMode}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      if (_crashlytics == null) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
        _crashlytics = FirebaseCrashlytics.instance;
      }
      await _crashlytics!.setCrashlyticsCollectionEnabled(enabled);
      _enabled = enabled;
    } catch (error) {
      AppLogger.warning('Crash reporting initialization unavailable',
          context: {'type': error.runtimeType.toString()});
    }
  }

  Future<void> recordError(Object error, StackTrace stack) async {
    if (!_enabled) return;
    try {
      await _crashlytics!
          .recordError(error, stack, fatal: true, printDetails: false);
    } catch (failure) {
      // Reporting must never replace the original failure with another error.
      AppLogger.warning('Crash report could not be recorded',
          context: {'type': failure.runtimeType.toString()});
    }
  }
}
