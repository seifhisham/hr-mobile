import 'package:hrmobile/src/imports/imports.dart';
import '../employee_navigation.dart';
import '../auth/providers/auth_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String? _validateCurrent(String? value) {
    if (value == null || value.isEmpty) return 'auth.password_required'.tr();
    return value.length > 128 ? 'auth.password_too_long'.tr() : null;
  }

  String? _validateNew(String? value) {
    if ((value?.length ?? 0) < 8) return 'account.password_minimum'.tr();
    return _validateCurrent(value);
  }

  String? _validateConfirmation(String? value) =>
      value != _newPassword.text ? 'auth.passwords_do_not_match'.tr() : null;
  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    ref.read(authControllerProvider.notifier).changePassword(
        currentPassword: _current.text, newPassword: _newPassword.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return AppScaffold(
      appBar: AppTopBar(title: 'account.change_password'.tr()),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.lg.w),
        child: AutofillGroup(
            child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmployeeHeading(
                        title: 'account.change_password'.tr(),
                        subtitle: 'design.security_hint'.tr(),
                        icon: Icons.lock_outline_rounded),
                    Text('account.password_notice'.tr()),
                    SizedBox(height: AppSpacing.lg.h),
                    AppPasswordField(
                        label: 'account.current_password'.tr(),
                        controller: _current,
                        enabled: !state.isLoading,
                        validator: _validateCurrent,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.next),
                    SizedBox(height: AppSpacing.md.h),
                    AppPasswordField(
                        label: 'account.new_password'.tr(),
                        controller: _newPassword,
                        enabled: !state.isLoading,
                        validator: _validateNew,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next),
                    SizedBox(height: AppSpacing.md.h),
                    AppPasswordField(
                        label: 'auth.confirm_password'.tr(),
                        controller: _confirmation,
                        enabled: !state.isLoading,
                        validator: _validateConfirmation,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
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
                        label: 'account.change_password'.tr(),
                        isFullWidth: true,
                        isLoading: state.isLoading,
                        onPressed: state.isLoading ? null : _submit),
                  ],
                ))),
      )),
    );
  }
}
