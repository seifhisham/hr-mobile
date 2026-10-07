import 'package:hrmobile/src/utils/utils.dart';
import '../models/user_model.dart';

abstract class AuthRepository {
  Stream<AppUser?> get onAuthStateChanged;
  FutureEither<AppUser> login(
      {required String email, required String password});
  FutureEither<AppUser?> checkAuthState();
  FutureEither<void> logout();
  FutureEither<void> changePassword(
      {required String currentPassword, required String newPassword});
}
