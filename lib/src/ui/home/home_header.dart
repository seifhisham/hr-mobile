import 'package:hodour/src/imports/imports.dart';
import '../../shared/widgets/app_logo.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/user_model.dart';
import '../notifications/notification_button.dart';
import '../attendance/attendance_provider.dart';
import '../attendance/attendance_summary.dart' show attendanceTime;

class HomeHeader extends ConsumerStatefulWidget {
  const HomeHeader({super.key, required this.user, this.child});
  final AppUser user;
  final Widget? child;
  @override
  ConsumerState<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<HomeHeader> {
  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final snapshot =
        user.employee == null ? null : ref.watch(attendanceProvider).snapshot;
    final colors = context.colors;
    final home = context.appColors;
    final name = user.employee?.name ?? user.name;
    final current = snapshot?.current;
    final schedule = current?.schedule ?? snapshot?.schedule;
    final status = switch (current) {
      null => 'attendance.not_checked_in_short',
      final record when record.checkOut != null => 'attendance.checked_out',
      _ => 'attendance.working',
    };
    final date = DateTime.tryParse(snapshot?.workDate ?? user.today);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: EdgeInsets.only(top: AppSpacing.sm),
        padding: EdgeInsets.fromLTRB(
            AppSpacing.ml, AppSpacing.ms, AppSpacing.ms, AppSpacing.xxl),
        decoration:
            BoxDecoration(color: home.homeBlue, borderRadius: AppBorders.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppLogo(size: AppSpacing.xl + AppSpacing.sm),
            SizedBox(width: AppSpacing.ms),
            Expanded(
                child: Text(user.companyName,
                    style: context.textTheme.headlineSmall?.copyWith(
                        color: home.onHomeBlue, fontWeight: FontWeight.w800))),
            NotificationButton(color: home.onHomeBlue, dotBadge: true),
            Semantics(
              label: 'account.title'.tr(),
              button: true,
              child: InkResponse(
                onTap: () => context.goNamed('account'),
                child: SizedBox.square(
                  dimension: AppSpacing.xxl,
                  child: Center(
                      child: AppAvatar(
                    initials: homeInitials(name),
                    radius: AppSpacing.ml,
                    backgroundColor: home.homeTrack,
                    foregroundColor: colors.onSurface,
                  )),
                ),
              ),
            ),
          ]),
          SizedBox(height: AppSpacing.sm),
          Semantics(
              header: true,
              child: Text(
                  homeGreeting(DateTime.now(), user.timezone).tr(namedArgs: {
                    'name': name.trim().split(RegExp(r'\s+')).first
                  }),
                  style: context.textTheme.headlineSmall?.copyWith(
                      color: home.onHomeBlue, fontWeight: FontWeight.w600))),
          if (date != null)
            Text(
                DateFormat('EEEE, d MMMM', context.locale.toString())
                    .format(date),
                semanticsLabel: snapshot?.workDate ?? user.today,
                style: context.textTheme.bodyLarge
                    ?.copyWith(color: home.onHomeBlue.withValues(alpha: 0.9))),
        ]),
      ),
      Transform.translate(
        offset: Offset(0, -(AppSpacing.xl + AppSpacing.sm)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: AppCard(
            key: const ValueKey('home-attendance-card'),
            showShadow: true,
            padding: EdgeInsets.fromLTRB(
                AppSpacing.ml, AppSpacing.ml, AppSpacing.ml, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (schedule != null) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.calendar_today_outlined,
                        color: colors.onSurfaceVariant, size: AppSpacing.lg),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('home.assigned_shift'.tr(),
                                style: context.textTheme.bodySmall?.copyWith(
                                    letterSpacing: 0,
                                    color: colors.onSurfaceVariant)),
                            Text('${schedule.start} – ${schedule.end}',
                                semanticsLabel:
                                    '${schedule.name}: ${schedule.start} – ${schedule.end}',
                                style: context.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        )),
                    SizedBox(width: AppSpacing.sm),
                    SizedBox(
                        height: AppSpacing.xl,
                        child: VerticalDivider(
                            width: AppSpacing.md,
                            color: colors.outlineVariant)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                        flex: 6,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                  padding: EdgeInsets.only(top: AppSpacing.xs),
                                  child: Icon(Icons.circle,
                                      size: AppSpacing.ms,
                                      color: current != null &&
                                              current.checkOut == null
                                          ? home.success
                                          : colors.onSurfaceVariant)),
                              SizedBox(width: AppSpacing.sm),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(status.tr(),
                                        style: context.textTheme.labelLarge
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700)),
                                    if (current != null &&
                                        current.checkOut == null)
                                      Text(
                                          'home.checked_in'.tr(namedArgs: {
                                            'time': attendanceTime(
                                                    current.checkIn,
                                                    current.timezone)
                                                .split(' ')
                                                .skip(1)
                                                .join(' ')
                                          }),
                                          style: context.textTheme.bodySmall
                                              ?.copyWith(
                                                  letterSpacing: 0,
                                                  color:
                                                      colors.onSurfaceVariant)),
                                  ])),
                            ])),
                  ]),
                  SizedBox(height: AppSpacing.ml),
                ],
                if (widget.child != null) widget.child!,
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

String homeInitials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part.characters.first)
    .join();

String homeGreeting(DateTime now, String timezone) {
  late final DateTime local;
  try {
    local = tz.TZDateTime.from(now, tz.getLocation(timezone));
  } on tz.LocationNotFoundException {
    local = now.toUtc();
  }
  return switch (local.hour) {
    < 12 => 'home.good_morning',
    < 18 => 'home.good_afternoon',
    _ => 'home.good_evening',
  };
}
