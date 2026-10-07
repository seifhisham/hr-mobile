import 'package:hrmobile/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../employee_navigation.dart';
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.userOrNull;
    if (user == null) return const SizedBox.shrink();
    final colors = context.colors;
    return AppScaffold(
      bottomNavigationBar: const EmployeeNavigation(index: 0),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: AppBorders.md),
                          child: Icon(Icons.spa_outlined,
                              color: colors.onPrimaryContainer)),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: Text(user.companyName,
                              style: context.textTheme.titleMedium)),
                      const ThemeToggleButton(),
                      const NotificationButton(),
                    ]),
                    SizedBox(height: AppSpacing.xl),
                    Text('design.welcome'.tr(),
                        style: context.textTheme.bodyLarge
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    SizedBox(height: AppSpacing.xs),
                    Text(user.employee?.name ?? user.name,
                        style: context.textTheme.headlineLarge),
                    SizedBox(height: AppSpacing.lg),
                    if (session
                        case SessionAuthenticated(
                          profileRefresh: RequestFailure(:final failure)
                        ))
                      Text(
                          '${'account.profile_stale'.tr()} ${failure.message}'),
                    AppCard(
                        color: colors.primary,
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: DefaultTextStyle.merge(
                            style: TextStyle(color: colors.onPrimary),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Icon(Icons.wb_sunny_outlined,
                                          color: colors.onPrimary)),
                                  SizedBox(height: AppSpacing.md),
                                  Text('design.your_workday'.tr(),
                                      style: context.textTheme.headlineSmall
                                          ?.copyWith(color: colors.onPrimary)),
                                  SizedBox(height: AppSpacing.sm),
                                  Text(user.today,
                                      style: context.textTheme.titleLarge
                                          ?.copyWith(color: colors.onPrimary)),
                                  Text(user.timezone),
                                  SizedBox(height: AppSpacing.lg),
                                  if (user.employee == null)
                                    Text('account.no_employee'.tr())
                                  else ...[
                                    Text(user.schedule == null
                                        ? 'account.no_schedule'.tr()
                                        : '${user.schedule!.name} · ${user.schedule!.start} – ${user.schedule!.end}'),
                                    SizedBox(height: AppSpacing.lg),
                                    AppButton(
                                        label: 'design.open_attendance'.tr(),
                                        color: colors.surface,
                                        textColor: colors.primary,
                                        onPressed: () =>
                                            context.goNamed('attendance')),
                                  ],
                                ]))),
                    SizedBox(height: AppSpacing.xl),
                    Text('design.quick_access'.tr(),
                        style: context.textTheme.titleLarge),
                    SizedBox(height: AppSpacing.md),
                    if (user.employee != null) ...[
                      _shortcut(
                          context,
                          Icons.description_outlined,
                          'design.manage_requests',
                          'design.requests_hint',
                          'requests'),
                      SizedBox(height: AppSpacing.md),
                    ],
                    _shortcut(
                        context,
                        Icons.person_outline_rounded,
                        'design.your_profile',
                        'design.profile_hint',
                        'account'),
                  ]))),
    );
  }

  Widget _shortcut(BuildContext context, IconData icon, String title,
          String subtitle, String route) =>
      AppCard(
        onTap: () => context.goNamed(route),
        child: Row(children: [
          Icon(icon, color: context.colors.primary),
          SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title.tr(), style: context.textTheme.titleMedium),
                SizedBox(height: AppSpacing.xs),
                Text(subtitle.tr(),
                    style: context.textTheme.bodyMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant))
              ])),
          SizedBox(width: AppSpacing.sm),
          Icon(Directionality.of(context) == TextDirection.rtl
              ? Icons.chevron_left_rounded
              : Icons.chevron_right_rounded),
        ]),
      );
}
