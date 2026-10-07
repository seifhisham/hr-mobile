import '../../services/auth_service.dart';
import '../../utils/utils.dart';
import '../models/user_model.dart';
import 'auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({AuthService? service})
      : _service = service ?? AuthService.instance;
  final AuthService _service;
  @override
  Stream<AppUser?> get onAuthStateChanged => _service.authStateChanges;
  @override
  FutureEither<AppUser> login(
          {required String email, required String password}) =>
      _service.login(email: email, password: password);
  @override
  FutureEither<AppUser?> checkAuthState() => _service.getCurrentUser();
  @override
  FutureEither<void> logout() => _service.logout();
  @override
  FutureEither<void> changePassword(
          {required String currentPassword, required String newPassword}) =>
      _service.changePassword(
          currentPassword: currentPassword, newPassword: newPassword);
}
