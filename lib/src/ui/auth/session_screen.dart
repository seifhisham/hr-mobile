import 'package:hodour/src/imports/imports.dart';
import 'providers/session_provider.dart';
import 'providers/auth_provider.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final action = ref.watch(authControllerProvider);
    return AppScaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      child: switch (session) {
        SessionUnavailable(:final failure) =>
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('auth.session_unavailable'.tr(),
                style: context.textTheme.titleLarge),
            SizedBox(height: AppSpacing.md.h),
            Semantics(
                liveRegion: true,
                child: Text(failure.message, textAlign: TextAlign.center)),
            SizedBox(height: AppSpacing.lg.h),
            AppButton(
                label: 'account.retry'.tr(),
                onPressed: action.isLoading
                    ? null
                    : () => ref.read(sessionProvider.notifier).restore()),
            AppTextButton(
                label: 'account.sign_out'.tr(),
                onPressed: action.isLoading
                    ? null
                    : () => ref.read(authControllerProvider.notifier).logout()),
          ]),
        _ => Column(mainAxisSize: MainAxisSize.min, children: [
            const AppCircularProgress(),
            SizedBox(height: AppSpacing.md.h),
            Text('auth.validating_session'.tr()),
          ]),
      },
    ))));
  }
}
