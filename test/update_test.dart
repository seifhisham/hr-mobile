import 'dart:async';

import 'package:app_version_update/data/models/app_version_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hodour/src/theme/theme.dart';
import 'package:hodour/src/ui/update/update_gate.dart';
import 'package:hodour/src/ui/update/update_provider.dart';
import 'package:hodour/src/utils/utils.dart';

void main() {
  test('serializes checks, blocks failure, and permits retry', () async {
    var calls = 0;
    var pending = Completer<Either<Failure, AppVersionResult?>>();
    final controller = UpdateController(() {
      calls++;
      return pending.future;
    }, supported: true);
    addTearDown(controller.dispose);
    expect(controller.state.isLoading, true);
    await controller.check();
    expect(calls, 1);
    pending.complete(const Left(NetworkFailure('Offline')));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isFailure, true);
    pending = Completer();
    final retry = controller.check();
    pending.complete(Right(AppVersionResult(canUpdate: false)));
    await retry;
    expect(controller.state.isSuccess, true);
  });

  test('missing store result cannot grant access', () async {
    final controller =
        UpdateController(() async => const Right(null), supported: true);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isFailure, true);
  });

  for (final canUpdate in [true, false]) {
    testWidgets('store update=$canUpdate controls access', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter_native_splash'), (_) async => null);
      final controller = UpdateController(
          () async => Right(AppVersionResult(
              canUpdate: canUpdate,
              storeUrl:
                  'https://play.google.com/store/apps/details?id=com.wsc.hodour')),
          supported: true);
      await tester.pumpWidget(ProviderScope(
        overrides: [updateProvider.overrideWith((ref) => controller)],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, child) => MaterialApp(
            theme: buildLightTheme(primaryColorHex: '#2457A7'),
            home: const UpdateGate(child: Scaffold(body: Text('Employee app'))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text('Employee app'), canUpdate ? findsNothing : findsOneWidget);
      expect(find.text('update.action'),
          canUpdate ? findsOneWidget : findsNothing);
      if (canUpdate) {
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Employee app'), findsNothing);
      }
    });
  }

  testWidgets('foreground recheck blocks a newly outdated app', (tester) async {
    var newerVersion = false;
    final controller = UpdateController(
        () async => Right(AppVersionResult(
            canUpdate: newerVersion,
            storeUrl: 'https://apps.apple.com/app/id123')),
        supported: true);
    await tester.pumpWidget(ProviderScope(
      overrides: [updateProvider.overrideWith((ref) => controller)],
      child: ScreenUtilInit(
        builder: (_, child) => MaterialApp(
          theme: buildDarkTheme(primaryColorHex: '#2457A7'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
          ),
          home: const UpdateGate(child: Scaffold(body: Text('Employee app'))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Employee app'), findsOneWidget);
    newerVersion = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Employee app'), findsNothing);
    expect(find.text('update.action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
