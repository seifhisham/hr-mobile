import 'package:hodour/src/imports/imports.dart';

class PrivacyPolicyButton extends StatelessWidget {
  const PrivacyPolicyButton({super.key});

  @override
  Widget build(BuildContext context) => AppButton(
        label: 'auth.privacy_policy'.tr(),
        variant: ButtonVariant.ghost,
        onPressed: () async {
          final result = await UrlLauncherService.instance
              .launch('https://wallstreetwsc.com/hodour-hr/privacy-policy');
          result.fold(
              (failure) =>
                  showGlobalToast(message: failure.message, status: 'warning'),
              (_) {});
        },
      );
}
