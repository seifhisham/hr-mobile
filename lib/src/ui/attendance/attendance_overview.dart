import 'package:hodour/src/imports/imports.dart';
import '../../data/models/attendance_totals.dart';

class AttendanceOverview extends StatelessWidget {
  const AttendanceOverview(
      {super.key, required this.totals, required this.filtered});
  final AttendanceTotals totals;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final foreground = context.appColors.onHomeBlue;
    Widget metric(IconData icon, int value, String label) => Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Icon(icon, color: foreground)),
          SizedBox(height: AppSpacing.sm),
          Text(
              NumberFormat.decimalPattern(context.locale.toString())
                  .format(value),
              style: context.textTheme.headlineSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700)),
          Text(label.tr(),
              style: context.textTheme.bodySmall?.copyWith(color: foreground)),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: AppSpacing.lg),
      Text('attendance.completed_time'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(color: foreground)),
      SizedBox(height: AppSpacing.xs),
      Text(
          'attendance.duration_value'.tr(namedArgs: {
            'hours': NumberFormat.decimalPattern(context.locale.toString())
                .format(totals.completedTime.inHours),
            'minutes': NumberFormat.decimalPattern(context.locale.toString())
                .format(totals.completedTime.inMinutes % 60),
          }),
          style: context.textTheme.displaySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()])),
      SizedBox(height: AppSpacing.md),
      Divider(color: foreground.withValues(alpha: 0.3)),
      SizedBox(height: AppSpacing.md),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        metric(Icons.event_available_outlined, totals.visits,
            'attendance.recorded_visits'),
        SizedBox(width: AppSpacing.md),
        metric(Icons.schedule_rounded, totals.lateArrivals,
            'attendance.late_arrivals'),
      ]),
      SizedBox(height: AppSpacing.lg),
      Text(
          (filtered ? 'attendance.filtered_scope' : 'attendance.overview_scope')
              .tr(),
          style: context.textTheme.bodySmall?.copyWith(color: foreground)),
    ]);
  }
}
