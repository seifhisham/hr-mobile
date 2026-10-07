import 'package:hrmobile/src/imports/imports.dart';
import 'providers/auth_provider.dart';
import '../../theme/theme_toggle_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    ref
        .read(authControllerProvider.notifier)
        .login(email: _email.text, password: _password.text);
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'auth.email_required'.tr();
    if (email.length > 254 || !AppUtils.isValidEmail(email)) {
      return 'auth.email_invalid'.tr();
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'auth.password_required'.tr();
    return value.length > 128 ? 'auth.password_too_long'.tr() : null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return AppScaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      child: AutofillGroup(
          child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: ThemeToggleButton()),
                  Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                              color: context.colors.primary,
                              borderRadius: AppBorders.xl),
                          child: Icon(Icons.spa_outlined,
                              color: context.colors.onPrimary,
                              size: AppSpacing.xxl))),
                  SizedBox(height: AppSpacing.xl),
                  Text('design.portal'.tr(),
                      style: context.textTheme.labelLarge
                          ?.copyWith(color: context.colors.primary)),
                  SizedBox(height: AppSpacing.md),
                  Text('auth.log_in'.tr(),
                      style: context.textTheme.headlineLarge),
                  SizedBox(height: AppSpacing.sm.h),
                  Text('auth.log_in_subtitle'.tr(),
                      style: context.textTheme.bodyLarge
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.xl.h),
                  AppTextField(
                      label: 'auth.email'.tr(),
                      controller: _email,
                      enabled: !state.isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      validator: _validateEmail),
                  SizedBox(height: AppSpacing.md.h),
                  AppPasswordField(
                      label: 'auth.password'.tr(),
                      controller: _password,
                      enabled: !state.isLoading,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => _submit()),
                  SizedBox(height: AppSpacing.lg.h),
                  if (state case RequestFailure(:final failure)) ...[
                    Semantics(
                        liveRegion: true,
                        child: Text(failure.message,
                            style: TextStyle(color: context.colors.error))),
                    SizedBox(height: AppSpacing.md.h),
                  ],
                  AppButton(
                      label: 'auth.sign_in'.tr(),
                      isFullWidth: true,
                      isLoading: state.isLoading,
                      onPressed: state.isLoading ? null : _submit),
                  SizedBox(height: AppSpacing.lg.h),
                  Text('auth.contact_hr'.tr(), textAlign: TextAlign.center),
                ],
              ))),
    ))));
  }
}
