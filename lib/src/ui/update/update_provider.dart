import 'package:app_version_update/data/models/app_version_result.dart';
import 'package:hodour/src/imports/imports.dart';

final updateCheckProvider =
    Provider<FutureEither<AppVersionResult?> Function()>(
        (ref) => () => VersionUpdateService.instance.checkForUpdate());

final updateProvider =
    StateNotifierProvider<UpdateController, RequestState<AppVersionResult?>>(
        (ref) {
  return UpdateController(ref.watch(updateCheckProvider),
      supported: !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));
});

class UpdateController extends StateNotifier<RequestState<AppVersionResult?>> {
  UpdateController(this._check, {required bool supported})
      : super(supported ? const RequestInitial() : const RequestSuccess(null)) {
    if (supported) check();
  }

  final FutureEither<AppVersionResult?> Function() _check;

  Future<void> check() async {
    if (state.isLoading) return;
    state = const RequestLoading();
    final result = await _check();
    if (!mounted) return;
    state = result.fold(RequestFailure.new, (data) {
      if (data == null) {
        return const RequestFailure(
            ServerFailure('Store returned no version information.'));
      }
      return RequestSuccess(data);
    });
  }
}
