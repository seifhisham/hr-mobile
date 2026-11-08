import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:hodour/src/services/biometric_service.dart';
import 'package:hodour/src/utils/failure.dart';

class FakeLocalAuthentication extends LocalAuthentication {
  bool available = true, enrolled = true, accepted = true;
  Object? error;
  int prompts = 0;
  @override
  Future<bool> get canCheckBiometrics async => available;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      enrolled ? [BiometricType.fingerprint] : [];
  @override
  Future<bool> authenticate(
      {required String localizedReason,
      authMessages = const [],
      AuthenticationOptions options = const AuthenticationOptions()}) async {
    prompts++;
    expect(options.biometricOnly, isTrue);
    expect(options.useErrorDialogs, isFalse);
    if (error != null) throw error!;
    return accepted;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeLocalAuthentication native;
  late BiometricService service;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {BiometricService.enabledKey: 'true'});
    native = FakeLocalAuthentication();
    service = BiometricService(authentication: native);
  });
  test('successful unlock prompts once until reset', () async {
    await service.unlock();
    await service.unlock();
    expect(native.prompts, 1);
    service.reset();
    await service.unlock();
    expect(native.prompts, 2);
  });
  test('disabled setting never prompts', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await service.unlock();
    expect(native.prompts, 0);
  });
  test('missing hardware or enrollment leaves session locked', () async {
    native.available = false;
    await expectLater(service.unlock(), throwsA(isA<BiometricFailure>()));
    native.available = true;
    native.enrolled = false;
    await expectLater(service.unlock(), throwsA(isA<BiometricFailure>()));
    expect(native.prompts, 0);
  });
  test('cancel and native lockout fail closed and allow retry', () async {
    native.accepted = false;
    await expectLater(service.unlock(), throwsA(isA<BiometricFailure>()));
    native.error = PlatformException(code: 'LockedOut');
    await expectLater(service.unlock(), throwsA(isA<BiometricFailure>()));
    native.error = null;
    native.accepted = true;
    await service.unlock();
    expect(native.prompts, 3);
  });
}
