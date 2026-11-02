import 'package:hodour/src/imports/imports.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/attendance_model.dart';

class AttendanceTimePair extends StatelessWidget {
  const AttendanceTimePair({super.key, required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    Widget time(String label, DateTime? value, IconData icon) => Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ExcludeSemantics(
                child: Icon(icon,
                    size: AppSpacing.md, color: context.colors.primary)),
            SizedBox(width: AppSpacing.xs),
            Expanded(
                child: Text(label.tr(),
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant))),
          ]),
          SizedBox(height: AppSpacing.sm),
          Text(
              value == null
                  ? 'attendance.open'.tr()
                  : attendanceClock(value, record.timezone),
              semanticsLabel: value == null
                  ? 'attendance.open'.tr()
                  : attendanceTime(value, record.timezone),
              style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        time('attendance.arrival', record.checkIn, Icons.login_rounded),
        SizedBox(width: AppSpacing.md),
        time('attendance.departure', record.checkOut, Icons.logout_rounded),
      ]),
      SizedBox(height: AppSpacing.sm),
      Text(record.timezone,
          style: context.textTheme.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant)),
    ]);
  }
}

String attendanceTime(DateTime timestamp, String timezone) {
  try {
    return DateFormat('yyyy-MM-dd HH:mm')
        .format(tz.TZDateTime.from(timestamp, tz.getLocation(timezone)));
  } on tz.LocationNotFoundException {
    return '${DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toUtc())} UTC';
  }
}

String attendanceClock(DateTime timestamp, String timezone) {
  try {
    return DateFormat('HH:mm:ss')
        .format(tz.TZDateTime.from(timestamp, tz.getLocation(timezone)));
  } on tz.LocationNotFoundException {
    return '${DateFormat('HH:mm:ss').format(timestamp.toUtc())} UTC';
  }
}

String attendanceStatus(String? status) => switch (status) {
      'On time' => 'attendance.on_time'.tr(),
      'Late' => 'attendance.late'.tr(),
      'Not scheduled' => 'attendance.not_scheduled'.tr(),
      'Missing check-out' => 'attendance.missing_checkout'.tr(),
      _ => status ?? '',
    };
