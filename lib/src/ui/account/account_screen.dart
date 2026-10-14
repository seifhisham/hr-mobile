import 'package:hrmobile/src/imports/imports.dart';
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';
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
      body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: () async {
                if (!ref.read(authControllerProvider).isLoading) {
                  await ref.read(sessionProvider.notifier).refresh();
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(AppSpacing.lg.w).copyWith(
                    bottom:
                        AppSpacing.lg.w + MediaQuery.paddingOf(context).bottom),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (session
                          case SessionAuthenticated(
                            profileRefresh: RequestFailure(:final failure)
                          ))
                        Text(
                            '${'account.profile_stale'.tr()} ${failure.message}'),
                      Row(children: [
                        Expanded(
                            child: Semantics(
                                header: true,
                                child: Text('account.title'.tr(),
                                    style: context.textTheme.headlineMedium))),
                        const ThemeToggleButton(),
                        const NotificationButton(),
                      ]),
                      SizedBox(height: AppSpacing.lg),
                      AppCard(
                          color: context.colors.primaryContainer,
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExcludeSemantics(
                                    child: Container(
                                        padding: EdgeInsets.all(AppSpacing.md),
                                        decoration: BoxDecoration(
                                            color: context.colors.surface,
                                            borderRadius: AppBorders.full),
                                        child: Icon(
                                            Icons.person_outline_rounded,
                                            size: AppSpacing.xl,
                                            color: context.colors.primary))),
                                SizedBox(height: AppSpacing.md),
                                Text(user.name,
                                    style: context.textTheme.headlineSmall
                                        ?.copyWith(
                                            color: context
                                                .colors.onPrimaryContainer)),
                                SizedBox(height: AppSpacing.xs),
                                Text(employee?.jobTitle ?? user.companyName,
                                    style: context.textTheme.bodyLarge
                                        ?.copyWith(
                                            color: context
                                                .colors.onPrimaryContainer)),
                                if (employee != null) ...[
                                  SizedBox(height: AppSpacing.md),
                                  Row(children: [
                                    Icon(
                                        employee.active
                                            ? Icons.check_circle_outline_rounded
                                            : Icons
                                                .pause_circle_outline_rounded,
                                        size: AppSpacing.ml,
                                        color:
                                            context.colors.onPrimaryContainer),
                                    SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                        child: Text(
                                            (employee.active
                                                    ? 'account.active'
                                                    : 'account.inactive')
                                                .tr(),
                                            style: context.textTheme.labelLarge
                                                ?.copyWith(
                                                    color: context.colors
                                                        .onPrimaryContainer))),
                                  ]),
                                ],
                              ])),
                      SizedBox(height: AppSpacing.lg),
                      AppCard(
                          title: 'design.your_profile'.tr(),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _detail('auth.email', user.email),
                                _detail('account.company', user.companyName),
                                _detail('account.timezone', user.timezone),
                                _detail('account.today', user.today),
                              ])),
                      SizedBox(height: AppSpacing.lg),
                      AppCard(
                          title: 'account.employment'.tr(),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (employee == null)
                                  Text('account.no_employee'.tr())
                                else ...[
                                  _detail('account.employee_number',
                                      employee.employeeNumber),
                                  _detail('account.national_id',
                                      employee.nationalId),
                                  _detail('account.department',
                                      employee.department),
                                  _detail(
                                      'account.job_title', employee.jobTitle),
                                  _detail(
                                      'account.start_date', employee.startDate),
                                  _detail(
                                      'account.status',
                                      employee.active
                                          ? 'account.active'.tr()
                                          : 'account.inactive'.tr()),
                                ],
                              ])),
                      if (employee != null) ...[
                        SizedBox(height: AppSpacing.lg),
                        AppCard(
                            title: 'account.schedule'.tr(),
                            leading: Icon(Icons.calendar_month_outlined,
                                color: context.colors.primary),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (schedule == null)
                                    Text('account.no_schedule'.tr())
                                  else ...[
                                    _detail('account.schedule', schedule.name),
                                    _detail('account.hours',
                                        '${schedule.start} – ${schedule.end} (${user.timezone})'),
                                    _detail(
                                        'account.days',
                                        schedule.days
                                            .map((day) =>
                                                'account.day_$day'.tr())
                                            .join(', ')),
                                    _detail(
                                        'account.grace',
                                        'account.grace_value'.tr(args: [
                                          schedule.graceMinutes.toString()
                                        ])),
                                  ],
                                ])),
                      ],
                      SizedBox(height: AppSpacing.lg.h),
                      AppButton(
                          label: 'account.change_password'.tr(),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          isFullWidth: true,
                          onPressed: action.isLoading
                              ? null
                              : () => context.pushNamed('changePassword')),
                      SizedBox(height: AppSpacing.md.h),
                      AppButton(
                          label: 'account.sign_out'.tr(),
                          prefixIcon: const Icon(Icons.logout_rounded),
                          variant: ButtonVariant.danger,
                          isFullWidth: true,
                          isLoading: action.isLoading,
                          onPressed: action.isLoading
                              ? null
                              : () => ref
                                  .read(authControllerProvider.notifier)
                                  .logout()),
                    ]),
              ))),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
              child: Container(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                      color: context.colors.primaryContainer,
                      borderRadius: AppBorders.lg),
                  child: Icon(
                      switch (label) {
                        'auth.email' => Icons.mail_outline_rounded,
                        'account.company' => Icons.business_outlined,
                        'account.timezone' ||
                        'account.hours' ||
                        'account.grace' =>
                          Icons.schedule_rounded,
                        'account.employee_number' ||
                        'account.national_id' =>
                          Icons.badge_outlined,
                        'account.department' => Icons.groups_outlined,
                        'account.job_title' => Icons.work_outline_rounded,
                        'account.status' => Icons.verified_user_outlined,
                        _ => Icons.calendar_today_outlined,
                      },
                      size: AppSpacing.ml,
                      color: context.colors.onPrimaryContainer))),
          SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label.tr(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                SizedBox(height: AppSpacing.xs),
                SelectableText(value,
                    style: Theme.of(context).textTheme.titleMedium),
              ])),
        ]),
      );
}
