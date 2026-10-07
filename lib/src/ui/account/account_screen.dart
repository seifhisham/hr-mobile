import 'package:hrmobile/src/imports/imports.dart';
import '../employee_navigation.dart';
import '../auth/providers/session_provider.dart';
import '../auth/providers/auth_provider.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(sessionProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.userOrNull;
    final action = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();
    final employee = user.employee;
    final schedule = user.schedule;
    return AppScaffold(
      bottomNavigationBar: const EmployeeNavigation(index: 3),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.lg.w),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (session
              case SessionAuthenticated(
                profileRefresh: RequestFailure(:final failure)
              ))
            Text('${'account.profile_stale'.tr()} ${failure.message}'),
          EmployeeHeading(
              title: user.name,
              subtitle: user.employee?.jobTitle ?? user.companyName,
              icon: Icons.person_outline_rounded),
          SizedBox(height: AppSpacing.md.h),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                _detail('auth.email', user.email),
                _detail('account.company', user.companyName),
                _detail('account.timezone', user.timezone),
                _detail('account.today', user.today),
                if (employee == null)
                  Text('account.no_employee'.tr())
                else ...[
                  _detail('account.employee_number', employee.employeeNumber),
                  _detail('account.national_id', employee.nationalId),
                  _detail('account.department', employee.department),
                  _detail('account.job_title', employee.jobTitle),
                  _detail('account.start_date', employee.startDate),
                  _detail(
                      'account.status',
                      employee.active
                          ? 'account.active'.tr()
                          : 'account.inactive'.tr()),
                  if (schedule == null)
                    Text('account.no_schedule'.tr())
                  else ...[
                    _detail('account.schedule', schedule.name),
                    _detail('account.hours',
                        '${schedule.start} – ${schedule.end} (${user.timezone})'),
                    _detail(
                        'account.days',
                        schedule.days
                            .map((day) => 'account.day_$day'.tr())
                            .join(', ')),
                    _detail(
                        'account.grace',
                        'account.grace_value'
                            .tr(args: [schedule.graceMinutes.toString()])),
                  ],
                ],
              ])),
          SizedBox(height: AppSpacing.lg.h),
          AppButton(
              label: 'account.change_password'.tr(),
              isFullWidth: true,
              onPressed: action.isLoading
                  ? null
                  : () => context.pushNamed('changePassword')),
          SizedBox(height: AppSpacing.md.h),
          AppButton(
              label: 'account.sign_out'.tr(),
              variant: ButtonVariant.outline,
              isFullWidth: true,
              isLoading: action.isLoading,
              onPressed: action.isLoading
                  ? null
                  : () => ref.read(authControllerProvider.notifier).logout()),
          AppTextButton(
              label: 'account.refresh'.tr(),
              onPressed: action.isLoading
                  ? null
                  : () => ref.read(sessionProvider.notifier).refresh()),
        ]),
      )),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.tr(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          SizedBox(height: AppSpacing.xs),
          SelectableText(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}
