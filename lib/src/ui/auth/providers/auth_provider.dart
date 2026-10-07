import 'package:hrmobile/src/imports/imports.dart';
import 'package:hrmobile/src/data/repositories/auth_repository.dart';
import 'session_provider.dart';

final authControllerProvider =
    StateNotifierProvider.autoDispose<AuthController, RequestState<void>>(
        (ref) => AuthController(repository: ref.read(authRepositoryProvider)));

class AuthController extends StateNotifier<RequestState<void>> {
  AuthController({required AuthRepository repository})
      : _repository = repository,
        super(const RequestInitial());
  final AuthRepository _repository;

  Future<void> login({required String email, required String password}) async {
    if (state.isLoading) return;
    state = const RequestLoading();
    final result = await _repository.login(email: email, password: password);
    if (mounted) {
      state =
          result.fold(RequestFailure.new, (_) => const RequestSuccess(null));
    }
  }

  Future<void> changePassword(
      {required String currentPassword, required String newPassword}) async {
    if (state.isLoading) return;
    state = const RequestLoading();
    final result = await _repository.changePassword(
        currentPassword: currentPassword, newPassword: newPassword);
    result.fold(
        (_) {},
        (_) => showGlobalToast(
            message: 'account.password_changed'.tr(), status: 'success'));
    if (mounted) {
      state =
          result.fold(RequestFailure.new, (_) => const RequestSuccess(null));
    }
  }

  Future<void> logout() async {
    if (state.isLoading) return;
    state = const RequestLoading();
    final result = await _repository.logout();
    result.fold(
        (failure) =>
            showGlobalToast(message: failure.message, status: 'warning'),
        (_) {});
    if (mounted) {
      state =
          result.fold(RequestFailure.new, (_) => const RequestSuccess(null));
    }
  }
}
