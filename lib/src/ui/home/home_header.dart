import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/user_model.dart';
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';
import '../attendance/attendance_provider.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot =
        user.employee == null ? null : ref.watch(attendanceProvider).snapshot;
    final colors = context.colors;
    final status = snapshot?.olderOpen != null
        ? 'attendance.missing_checkout'
        : switch (snapshot?.current) {
            null => 'attendance.not_checked_in_short',
            final record when record.checkOut != null =>
              'attendance.checked_out',
            _ => 'attendance.working',
          };
    return AppCard(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
              child: Text('design.welcome'.tr(),
                  style: context.textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant))),
          const ThemeToggleButton(),
          const NotificationButton(),
        ]),
        Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                  header: true,
                  child: Text(user.employee?.name ?? user.name,
                      style: context.textTheme.headlineSmall)),
              if (user.employee case final employee?)
                Semantics(
                    label:
                        '${'account.employee_number'.tr()}: ${employee.employeeNumber}',
                    excludeSemantics: true,
                    child: AppBadge(
                        label: employee.employeeNumber,
                        color: colors.primaryContainer,
                        textColor: colors.onPrimaryContainer)),
            ]),
        SizedBox(height: AppSpacing.xs),
        Text(user.companyName,
            style: context.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant)),
        if (snapshot != null) ...[
          SizedBox(height: AppSpacing.md),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
                color: colors.primaryContainer, borderRadius: AppBorders.full),
            child: Text(status.tr(),
                style: context.textTheme.labelLarge
                    ?.copyWith(color: colors.onPrimaryContainer)),
          ),
          SizedBox(height: AppSpacing.md),
          const AppDivider(),
          SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
            _detail(context, Icons.calendar_today_outlined, snapshot.workDate),
            _detail(context, Icons.schedule_rounded,
                '${snapshot.schedule.name}: ${snapshot.schedule.start} – ${snapshot.schedule.end}'),
          ]),
        ],
      ],
    ));
  }

  Widget _detail(BuildContext context, IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            size: context.textTheme.bodySmall?.fontSize,
            color: context.colors.primary),
        SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(text, style: context.textTheme.bodySmall)),
      ]);
}
