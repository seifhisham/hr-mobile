import 'package:hrmobile/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_summary.dart';
import '../attendance/attendance_provider.dart';
import '../sales/sales_provider.dart';
import 'home_header.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.userOrNull;
    final salesAccess = accessValue(ref.watch(salesAccessProvider));
    if (user == null) return const SizedBox.shrink();
    return AppScaffold(
      body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: () => ref.read(attendanceProvider.notifier).refresh(),
              child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(AppSpacing.lg).copyWith(
                      bottom:
                          AppSpacing.lg + MediaQuery.paddingOf(context).bottom),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeHeader(user: user),
                        SizedBox(height: AppSpacing.lg),
                        if (session
                            case SessionAuthenticated(
                              profileRefresh: RequestFailure(:final failure)
                            ))
                          Text(
                              '${'account.profile_stale'.tr()} ${failure.message}'),
                        if (user.employee == null)
                          AppCard(child: Text('account.no_employee'.tr()))
                        else ...[
                          const AttendanceSummary(homeStyle: true),
                        ],
                        SizedBox(height: AppSpacing.xl),
                        Text('design.quick_access'.tr(),
                            style: context.textTheme.titleLarge),
                        SizedBox(height: AppSpacing.md),
                        if (user.employee != null) ...[
                          _shortcut(context, Icons.home_work_outlined,
                              'sales.title', 'sales.subtitle', 'sales'),
                          SizedBox(height: AppSpacing.md),
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
                        if (user.employee == null && salesAccess.canReview) ...[
                          SizedBox(height: AppSpacing.md),
                          _shortcut(
                              context,
                              Icons.home_work_outlined,
                              'sales.team_title',
                              'sales.team_hint',
                              'teamSales'),
                        ],
                      ])))),
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
