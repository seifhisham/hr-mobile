import 'package:hodour/src/imports/imports.dart';
import '../../data/models/admin_dashboard.dart';
import '../../data/models/employee_request.dart';
import '../auth/providers/session_provider.dart';
import '../employee_navigation.dart';
import '../requests/request_widgets.dart' show requestTypeLabel;
import 'admin_dashboard_provider.dart';
import 'admin_dashboard_widgets.dart';

/// Company-wide analytics for admin accounts.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).userOrNull;
    final state = ref.watch(adminDashboardProvider);
    final allowed = ref.watch(isAdminProvider);
    return AppScaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(adminDashboardProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxxl +
                    AppSpacing.xxl +
                    MediaQuery.paddingOf(context).bottom),
            children: [
              EmployeeHeading(
                  title: 'admin.title'.tr(),
                  subtitle: user == null
                      ? 'admin.subtitle_generic'.tr()
                      : 'admin.subtitle'.tr(namedArgs: {
                          'company': user.companyName,
                          'date': user.today
                        }),
                  icon: Icons.insights_rounded),
              if (!allowed)
                AppEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'admin.not_allowed'.tr())
              else
                switch (state) {
                  RequestInitial() || RequestLoading() => Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xl),
                      child: AppLoading(message: 'admin.loading'.tr())),
                  RequestFailure(:final failure) => AppErrorWidget(
                      title: 'admin.load_failed'.tr(),
                      message: failure.message,
                      onRetry: () =>
                          ref.read(adminDashboardProvider.notifier).refresh()),
                  RequestSuccess(:final data) => _DashboardBody(data: data),
                },
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});
  final AdminDashboard data;

  @override
  Widget build(BuildContext context) {
    final today = data.todaySnapshot;
    final colors = context.colors;
    final appColors = context.appColors;
    final pending = data.pending;
    final sales = data.salesTotals;
    final attentionCount = (pending?.total ?? 0) +
        data.openPastVisits.length +
        data.outsideZone.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Today at a glance.
      DashboardSection(
        title: 'admin.today'.tr(),
        subtitle: 'admin.today_hint'.tr(),
        icon: Icons.today_rounded,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DashboardRate(
              label: 'admin.attendance_rate'.tr(),
              value: today.attendanceRate,
              detail: 'admin.of_expected'.tr(namedArgs: {
                'present': '${today.present}',
                'expected': '${today.scheduled - today.onLeave}'
              })),
          SizedBox(height: AppSpacing.md),
          DashboardGrid(children: [
            DashboardMetric(
                label: 'admin.present'.tr(),
                value: '${today.present}',
                tone: DashboardTone.good,
                caption: 'admin.still_working'
                    .tr(namedArgs: {'count': '${today.working}'})),
            DashboardMetric(
                label: 'admin.late'.tr(),
                value: '${today.late}',
                tone: today.late > 0
                    ? DashboardTone.waiting
                    : DashboardTone.neutral,
                caption: 'admin.punctuality'
                    .tr(namedArgs: {'rate': percentLabel(today.punctuality)})),
            DashboardMetric(
                label: 'admin.not_checked_in'.tr(),
                value: '${today.absent}',
                tone: today.absent > 0
                    ? DashboardTone.attention
                    : DashboardTone.neutral),
            DashboardMetric(
                label: 'admin.on_leave'.tr(), value: '${today.onLeave}'),
          ]),
        ]),
      ),

      // Things an admin should act on.
      DashboardSection(
        title: 'admin.attention'.tr(),
        subtitle: attentionCount == 0
            ? 'admin.attention_clear'.tr()
            : 'admin.attention_hint'.tr(),
        icon: Icons.priority_high_rounded,
        child: DashboardGrid(children: [
          DashboardMetric(
              label: 'admin.pending_requests'.tr(),
              value: pending == null ? '--' : '${pending.total}',
              tone: (pending?.total ?? 0) > 0
                  ? DashboardTone.waiting
                  : DashboardTone.neutral,
              caption: pending == null ? 'admin.unavailable'.tr() : null),
          DashboardMetric(
              label: 'admin.open_visits'.tr(),
              value: '${data.openPastVisits.length}',
              tone: data.openPastVisits.isNotEmpty
                  ? DashboardTone.attention
                  : DashboardTone.neutral),
          DashboardMetric(
              label: 'admin.outside_zone'.tr(),
              value: '${data.outsideZone.length}',
              tone: data.outsideZone.isNotEmpty
                  ? DashboardTone.attention
                  : DashboardTone.neutral),
          DashboardMetric(
              label: 'admin.frequent_late'.tr(),
              value: '${data.frequentLate.length}',
              tone: data.frequentLate.isNotEmpty
                  ? DashboardTone.waiting
                  : DashboardTone.neutral),
        ]),
      ),

      // Weekly trend.
      DashboardSection(
        title: 'admin.week_trend'.tr(),
        subtitle: 'admin.week_trend_hint'.tr(namedArgs: {
          'hours': data.averageHours == null
              ? '--'
              : data.averageHours!.toStringAsFixed(1)
        }),
        icon: Icons.bar_chart_rounded,
        child: AttendanceTrendChart(days: data.trend, today: data.today),
      ),

      // Departments.
      DashboardSection(
        title: 'admin.departments'.tr(),
        subtitle: 'admin.departments_hint'.tr(),
        icon: Icons.apartment_rounded,
        child: data.departments.isEmpty
            ? Text('admin.no_departments'.tr(),
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < data.departments.length; i++) ...[
                  if (i > 0) SizedBox(height: AppSpacing.ms),
                  DashboardRate(
                      label: data.departments[i].name,
                      value: data.departments[i].rate,
                      detail: '${data.departments[i].present}/'
                          '${data.departments[i].expected}'),
                ],
              ]),
      ),

      // Who has not checked in.
      DashboardSection(
        title: 'admin.not_checked_in_list'.tr(),
        subtitle: 'admin.not_checked_in_hint'.tr(),
        icon: Icons.person_off_outlined,
        child: DashboardList<AttendanceReportRow>(
          items: data.notCheckedIn,
          emptyText: 'admin.everyone_in'.tr(),
          itemBuilder: (context, row) =>
              DashboardPersonRow(name: row.name, subtitle: _place(row)),
        ),
      ),

      // Late arrivals today.
      DashboardSection(
        title: 'admin.late_today'.tr(),
        icon: Icons.schedule_rounded,
        child: DashboardList<AttendanceReportRow>(
          items: data.lateToday,
          emptyText: 'admin.no_late'.tr(),
          itemBuilder: (context, row) => DashboardPersonRow(
              name: row.name,
              subtitle: _place(row),
              trailing: dashboardClock(row.checkIn, row.timezone),
              trailingColor: appColors.warning),
        ),
      ),

      if (data.outsideZone.isNotEmpty)
        DashboardSection(
          title: 'admin.outside_zone_list'.tr(),
          subtitle: 'admin.outside_zone_hint'.tr(),
          icon: Icons.wrong_location_outlined,
          child: DashboardList<AttendanceReportRow>(
            items: data.outsideZone,
            emptyText: '',
            itemBuilder: (context, row) => DashboardPersonRow(
                name: row.name,
                subtitle: _place(row),
                trailing: dashboardClock(row.checkIn, row.timezone)),
          ),
        ),

      if (data.openPastVisits.isNotEmpty)
        DashboardSection(
          title: 'admin.open_visits_list'.tr(),
          subtitle: 'admin.open_visits_hint'.tr(),
          icon: Icons.history_toggle_off_rounded,
          child: DashboardList<AttendanceReportRow>(
            items: data.openPastVisits,
            emptyText: '',
            itemBuilder: (context, row) => DashboardPersonRow(
                name: row.name,
                subtitle: _place(row),
                trailing: row.workDate,
                trailingColor: colors.error),
          ),
        ),

      if (data.frequentLate.isNotEmpty)
        DashboardSection(
          title: 'admin.frequent_late_list'.tr(),
          subtitle: 'admin.frequent_late_hint'.tr(),
          icon: Icons.running_with_errors_rounded,
          child: DashboardList(
            items: data.frequentLate,
            emptyText: '',
            itemBuilder: (context, streak) => DashboardPersonRow(
                name: streak.name,
                subtitle: streak.department,
                trailing:
                    'admin.times'.tr(namedArgs: {'count': '${streak.count}'}),
                trailingColor: appColors.warning),
          ),
        ),

      // Pending requests.
      DashboardSection(
        title: 'admin.requests'.tr(),
        subtitle: pending == null
            ? 'admin.requests_unavailable'.tr()
            : 'admin.requests_hint'
                .tr(namedArgs: {'count': '${pending.total}'}),
        icon: Icons.pending_actions_rounded,
        child: pending == null
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (data.pendingByType.isNotEmpty) ...[
                  Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final (type, count) in data.pendingByType)
                          DashboardTag(
                              label: '${requestTypeLabel(type)} · $count'),
                      ]),
                  SizedBox(height: AppSpacing.sm),
                ],
                DashboardList<EmployeeRequest>(
                  items: pending.items,
                  emptyText: 'admin.no_pending'.tr(),
                  itemBuilder: (context, request) => DashboardPersonRow(
                      name: request.employeeName,
                      subtitle: [
                        requestTypeLabel(request.type),
                        if (request.from != null)
                          request.from == request.to || request.to == null
                              ? request.from!
                              : '${request.from} – ${request.to}',
                      ].join(' · ')),
                ),
              ]),
      ),

      // Workforce.
      DashboardSection(
        title: 'admin.workforce'.tr(),
        icon: Icons.groups_rounded,
        child: DashboardGrid(children: [
          DashboardMetric(
              label: 'admin.active_employees'.tr(),
              value: '${data.activeEmployees}',
              caption: data.inactiveEmployees > 0
                  ? 'admin.inactive'
                      .tr(namedArgs: {'count': '${data.inactiveEmployees}'})
                  : null),
          DashboardMetric(
              label: 'admin.department_count'.tr(),
              value: '${data.departmentCount}'),
          DashboardMetric(
              label: 'admin.new_hires'.tr(),
              value: '${data.newHiresThisMonth}',
              tone: data.newHiresThisMonth > 0
                  ? DashboardTone.good
                  : DashboardTone.neutral),
          DashboardMetric(
              label: 'admin.sales_team'.tr(),
              value: '${data.salesEnabledCount}'),
        ]),
      ),

      // Sales this month.
      DashboardSection(
        title: 'admin.sales'.tr(),
        subtitle: sales == null
            ? 'admin.sales_unavailable'.tr()
            : 'admin.sales_hint'.tr(),
        icon: Icons.trending_up_rounded,
        action: sales == null
            ? null
            : AppTextButton(
                label: 'admin.open'.tr(),
                onPressed: () => context.pushNamed('teamSales')),
        child: sales == null
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DashboardGrid(children: [
                  DashboardMetric(
                      label: 'admin.meetings'.tr(), value: '${sales.meetings}'),
                  DashboardMetric(
                      label: 'admin.deals'.tr(),
                      value: '${sales.deals}',
                      tone: sales.deals > 0
                          ? DashboardTone.good
                          : DashboardTone.neutral),
                  DashboardMetric(
                      label: 'admin.sales_pending'.tr(),
                      value: '${sales.pending}',
                      tone: sales.pending > 0
                          ? DashboardTone.waiting
                          : DashboardTone.neutral),
                  DashboardMetric(
                      label: 'admin.sales_returned'.tr(),
                      value: '${sales.returned}',
                      tone: sales.returned > 0
                          ? DashboardTone.attention
                          : DashboardTone.neutral),
                ]),
                if (sales.top.isNotEmpty) ...[
                  SizedBox(height: AppSpacing.md),
                  Text('admin.top_performers'.tr(),
                      style: context.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  for (final row in sales.top)
                    DashboardPersonRow(
                        name: row.employeeName,
                        subtitle: 'admin.meetings_count'
                            .tr(namedArgs: {'count': '${row.meetingTotal}'}),
                        trailing: 'admin.deals_count'
                            .tr(namedArgs: {'count': '${row.deals}'}),
                        trailingColor: appColors.success),
                ],
              ]),
      ),
    ]);
  }

  static String _place(AttendanceReportRow row) => [
        if (row.department.isNotEmpty) row.department,
        if (row.branchName != null && row.branchName!.isNotEmpty)
          row.branchName!,
      ].join(' · ');
}
