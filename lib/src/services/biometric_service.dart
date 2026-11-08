import 'package:easy_localization/easy_localization.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';
import '../utils/utils.dart';

class BiometricService {
  BiometricService({LocalAuthentication? authentication})
      : _authentication = authentication ?? LocalAuthentication();
  static final instance = BiometricService();
  static const enabledKey = 'session_biometric_unlock';
  final LocalAuthentication _authentication;
  Future<void>? _pending;
  bool _unlocked = false;
  int _generation = 0;

  Future<bool> isEnabled() async =>
      (await SecureStorageService.instance.read(enabledKey))
          .fold((failure) => throw failure, (value) => value == 'true');

  Future<void> authenticate() async {
    try {
      if (!await _authentication.canCheckBiometrics ||
          (await _authentication.getAvailableBiometrics()).isEmpty ||
          !await _authentication.authenticate(
              localizedReason: 'auth.biometric_reason'.tr(),
              options: const AuthenticationOptions(
                  biometricOnly: true, useErrorDialogs: false))) {
        throw const BiometricFailure();
      }
    } on BiometricFailure {
      rethrow;
    } catch (error) {
      AppLogger.warning('Biometric authentication unavailable',
          category: LogCategory.auth);
      throw const BiometricFailure();
    }
  }

  Future<void> unlock() async {
    if (_unlocked || !await isEnabled()) return;
    final generation = _generation;
    final pending = _pending ??= authenticate();
    try {
      await pending;
      if (generation != _generation) throw const BiometricFailure();
      _unlocked = true;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void reset() {
    _generation++;
    _unlocked = false;
    _pending = null;
  }
}
