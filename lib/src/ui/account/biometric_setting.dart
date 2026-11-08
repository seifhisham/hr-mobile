import 'package:hodour/src/imports/imports.dart';

class BiometricSetting extends StatefulWidget {
  const BiometricSetting({super.key});
  @override
  State<BiometricSetting> createState() => _BiometricSettingState();
}

class _BiometricSettingState extends State<BiometricSetting> {
  RequestState<bool> _state = const RequestLoading();
  bool _enabled = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await AuthService.instance.biometricEnabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _state = RequestSuccess(enabled);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _state = RequestFailure(Failure.fromException(error)));
      }
    }
  }

  Future<void> _change(bool enabled) async {
    setState(() => _state = const RequestLoading());
    final result = await AuthService.instance.setBiometricEnabled(enabled);
    if (!mounted) return;
    setState(() => _state = result.fold(RequestFailure.new, (_) {
          _enabled = enabled;
          return RequestSuccess(enabled);
        }));
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
              child: AppSwitch(
                  value: _enabled,
                  label: 'auth.biometric_setting'.tr(),
                  enabled: !_state.isLoading,
                  onChanged: _change)),
          Text('auth.biometric_hint'.tr(), style: context.textTheme.bodySmall),
          if (_state case RequestFailure(:final failure))
            Semantics(
                liveRegion: true,
                child: Text(
                    failure is BiometricFailure
                        ? failure.message.tr()
                        : failure.message,
                    style: TextStyle(color: context.colors.error))),
        ],
      );
}
