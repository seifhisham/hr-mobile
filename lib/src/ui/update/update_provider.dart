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
  AppVersionResult? _requiredUpdate;

  Future<void> check() async {
    if (state.isLoading) return;
    state = const RequestLoading();
    final result = await _check();
    if (!mounted) return;
    // A first release has no public listing; keep only confirmed updates blocking.
    state = result.fold((failure) {
      AppLogger.warning('Store update check unavailable',
          context: {'type': failure.runtimeType.toString()});
      return RequestSuccess(_requiredUpdate);
    }, (data) {
      if (data?.canUpdate != null) {
        _requiredUpdate = data!.canUpdate! ? data : null;
      }
      return RequestSuccess(_requiredUpdate);
    });
  }
}
