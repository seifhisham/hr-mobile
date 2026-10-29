import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/services/auth_service.dart';

/// Opt-in: run only against the throwaway backend created by the verification harness.
/// flutter test test/auth_backend_test.dart --dart-define=AUTH_TEST_API=http://127.0.0.1:PORT/api
class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('AUTH_TEST_API');
  test(
      'real REST employee session: login, restore, password verification/revocation, logout',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(Uri.parse(base).host, '127.0.0.1',
          reason: 'Use an isolated local test backend only.');
      FlutterSecureStorage.setMockInitialValues({});
      final client = Dio(BaseOptions(baseUrl: base));
      final auth = AuthService(client: client)..initialize();
      addTearDown(() {
        auth.dispose();
        client.close(force: true);
      });
      final login = await auth.login(
          workspace: const String.fromEnvironment('TEST_WORKSPACE',
              defaultValue: 'test-company'),
          email: 'mobile-employee@example.test',
          password: 'Isolated-employee-password-2026');
      expect(login.isRight(), isTrue);
      final user = login.getOrElse((failure) => throw failure);
      expect(user.employee!.nationalId, '00123456789012');
      expect(user.employee!.employeeNumber, 'EMP-000001');
      expect(user.companyName, 'Company HR');
      expect(user.timezone, 'Africa/Cairo');
      expect(user.schedule!.start, '10:00');
      final restoredClient = Dio(BaseOptions(baseUrl: base));
      final restored = AuthService(client: restoredClient)..initialize();
      addTearDown(() {
        restored.dispose();
        restoredClient.close(force: true);
      });
      expect(
          (await restored.getCurrentUser())
              .getOrElse((failure) => throw failure),
          user);
      final incorrect = await auth.changePassword(
          currentPassword: 'incorrect',
          newPassword: 'Updated-test-password-2026');
      expect(incorrect.isLeft(), isTrue);
      expect((await auth.getCurrentUser()).isRight(), isTrue);
      expect(
          (await auth.changePassword(
                  currentPassword: 'Isolated-employee-password-2026',
                  newPassword: 'Updated-test-password-2026'))
              .isRight(),
          isTrue);
      expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
          isNull);
      expect((await restored.getCurrentUser()).isLeft(), isTrue,
          reason: 'Backend must revoke all sessions.');
      expect(
          (await auth.login(
                  workspace: const String.fromEnvironment('TEST_WORKSPACE',
                      defaultValue: 'test-company'),
                  email: 'mobile-employee@example.test',
                  password: 'Updated-test-password-2026'))
              .isRight(),
          isTrue);
      expect((await auth.logout()).isRight(), isTrue);
      expect(await const FlutterSecureStorage().read(key: AuthService.tokenKey),
          isNull);
    }, _RealHttpOverrides());
  },
      skip:
          base.isEmpty ? 'Requires an isolated backend; see SETUP.md.' : false);
}
