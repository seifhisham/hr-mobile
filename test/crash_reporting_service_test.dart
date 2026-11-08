import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/services/crash_reporting_service.dart';

class FakeCrashlytics implements FirebaseCrashlytics {
  final reports = <Object>[];
  final collection = <bool>[];
  bool fail = false;
  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    if (fail) throw StateError('Native SDK unavailable');
    collection.add(enabled);
  }

  @override
  Future<void> recordError(dynamic exception, StackTrace? stack,
      {dynamic reason,
      Iterable<Object> information = const [],
      bool? printDetails,
      bool fatal = false}) async {
    if (fail) throw StateError('Native SDK unavailable');
    expect(fatal, isTrue);
    expect(printDetails, isFalse);
    expect(stack, isNotNull);
    reports.add(exception as Object);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeCrashlytics sdk;
  late CrashReportingService service;
  setUp(() {
    sdk = FakeCrashlytics();
    service = CrashReportingService(crashlytics: sdk);
  });
  test('debug and uninitialized reporting are disabled', () async {
    await service.recordError(StateError('early'), StackTrace.current);
    await service.initialize();
    await service.recordError(StateError('debug'), StackTrace.current);
    expect(sdk.collection, [false]);
    expect(sdk.reports, isEmpty);
    expect(service.enabled, isFalse);
  });
  test('release reporting forwards original error and stack as fatal',
      () async {
    await service.initialize(enabled: true);
    final error = StateError('test failure');
    await service.recordError(error, StackTrace.current);
    expect(sdk.collection, [true]);
    expect(sdk.reports, [same(error)]);
    expect(service.enabled, isTrue);
  });
  test('SDK failures do not escape into the global error handlers', () async {
    sdk.fail = true;
    await service.initialize(enabled: true);
    expect(service.enabled, isFalse);
    sdk.fail = false;
    await service.initialize(enabled: true);
    sdk.fail = true;
    await service.recordError(StateError('original'), StackTrace.current);
  });
  test('unsupported platforms do not initialize Crashlytics', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await service.initialize(enabled: true);
    expect(service.enabled, isFalse);
    expect(sdk.collection, isEmpty);
  });
}
