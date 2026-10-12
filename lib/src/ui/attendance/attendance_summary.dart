import 'package:hrmobile/src/imports/imports.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/attendance_model.dart';
import 'attendance_provider.dart';
import 'attendance_work_progress.dart';

class AttendanceSummary extends ConsumerStatefulWidget {
  const AttendanceSummary({super.key, this.homeStyle = false});
  final bool homeStyle;
  @override
  ConsumerState<AttendanceSummary> createState() => _AttendanceSummaryState();
}

class _AttendanceSummaryState extends ConsumerState<AttendanceSummary>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ringController;
  late final Animation<double> _ringWave;

  @override
  void initState() {
    super.initState();
    _ringController =
        AnimationController(vsync: this, duration: AppDurations.medium);
    _ringWave = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1)
              .chain(CurveTween(curve: AppCurves.decelerate)),
          weight: 35),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1, end: 0)
              .chain(CurveTween(curve: AppCurves.smooth)),
          weight: 65),
    ]).animate(_ringController);
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addObserver(this);
    ref.read(attendanceCaptureProvider).discardLostCapture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.homeStyle) {
        ref.read(attendanceProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(attendanceProvider.notifier).refresh();
    } else {
      _ringController.reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _ringController.reset();
  }

  void _repelRings() {
    if (!MediaQuery.disableAnimationsOf(context) &&
        !_ringController.isAnimating) {
      _ringController.forward(from: 0);
    }
  }

  Widget _actionRing(
          {required Color color,
          required double padding,
          required double expansion,
          required String name,
          required Widget child}) =>
      Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        Positioned.fill(
            child: IgnorePointer(
                child: AnimatedBuilder(
          animation: _ringWave,
          builder: (context, child) => Transform.scale(
              key: ValueKey(name),
              scale: 1 + expansion * _ringWave.value,
              child: child),
          child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        ))),
        Padding(padding: EdgeInsets.all(padding), child: child),
      ]);

  @override
  Widget build(BuildContext context) {
    ref.listen(attendanceProvider.select((state) => state.action), (_, next) {
      if (next case RequestFailure(failure: final CaptureFailure failure)) {
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          showGlobalToast(
              message: failure.message.tr(),
              status: 'error',
              duration: const Duration(seconds: 5));
        }
      }
    });
    final state = ref.watch(attendanceProvider);
    final snapshot = state.snapshot;
    if (widget.homeStyle) return _homeSummary(context, state, snapshot);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.noticeKey case final key?)
        Semantics(
            liveRegion: true,
            child: Text(key.tr(), style: context.textTheme.titleMedium)),
      if (state.data.isLoading && snapshot == null)
        const Center(child: CircularProgressIndicator()),
      if (state.data case RequestFailure(:final failure))
        Text(failure.message, style: TextStyle(color: context.colors.error)),
      if (snapshot != null) ...[
        AppCard(
            title: 'attendance.workday'.tr(),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(snapshot.workDate, style: context.textTheme.headlineSmall),
              SizedBox(height: AppSpacing.sm.h),
              if (snapshot.olderOpen == null &&
                  snapshot.current?.checkOut == null)
                AppButton(
                    label: (snapshot.current == null
                            ? 'attendance.check_in'
                            : 'attendance.check_out')
                        .tr(),
                    height: ButtonSize.large,
                    isFullWidth: true,
                    prefixIcon: Icon(
                        snapshot.current == null
                            ? Icons.login_rounded
                            : Icons.logout_rounded,
                        color: context.colors.onPrimary),
                    isLoading: state.action.isLoading,
                    onPressed: state.busy || state.pending != null
                        ? null
                        : () => ref.read(attendanceProvider.notifier).submit()),
              SizedBox(height: AppSpacing.md.h),
              Text(
                  '${snapshot.schedule.name}: ${snapshot.schedule.start} – ${snapshot.schedule.end}'),
              if (snapshot.current case final current?) ...[
                Text(attendanceStatus(current.status)),
                Text(
                    '${'attendance.check_in'.tr()}: ${attendanceTime(current.checkIn, current.timezone)}'),
                Text(
                    '${'attendance.check_out'.tr()}: ${current.checkOut == null ? 'attendance.open'.tr() : attendanceTime(current.checkOut!, current.timezone)}'),
                Text(current.timezone),
                if (current.checkOut == null &&
                    current.status == 'Missing check-out')
                  AppTextButton(
                      label: 'requests.types.forgotten_check_out'.tr(),
                      onPressed: () => context.pushNamed('newRequest',
                          queryParameters: {'attendanceId': current.id})),
              ] else
                Text('attendance.not_checked_in'.tr()),
              SizedBox(height: AppSpacing.md.h),
              if (snapshot.olderOpen case final record?) ...[
                Text('attendance.older_open'
                    .tr(namedArgs: {'date': record.workDate})),
                AppTextButton(
                    label: 'requests.types.forgotten_check_out'.tr(),
                    onPressed: () => context.pushNamed('newRequest',
                        queryParameters: {'attendanceId': record.id})),
              ] else if (snapshot.current?.checkOut != null)
                Text('attendance.completed'.tr())
              else ...[
                Text('attendance.capture_explanation'.tr(namedArgs: {
                  'radius': snapshot.policy.radiusMeters.toStringAsFixed(0),
                  'accuracy':
                      snapshot.policy.maxAccuracyMeters.toStringAsFixed(0)
                })),
                SizedBox(height: AppSpacing.md.h),
              ],
            ])),
        if (state.action case RequestFailure(:final failure)) ...[
          SizedBox(height: AppSpacing.md.h),
          Text(
              failure is CaptureFailure
                  ? failure.message.tr()
                  : failure.message,
              style: TextStyle(color: context.colors.error)),
          if (failure case CaptureFailure(:final recovery)
              when recovery != CaptureRecovery.retry)
            AppButton(
                label: 'attendance.open_settings'.tr(),
                variant: ButtonVariant.outline,
                onPressed: () =>
                    ref.read(attendanceCaptureProvider).openSettings(recovery)),
        ],
      ],
    ]);
  }

  Widget _homeSummary(BuildContext context, AttendanceState state,
      AttendanceSnapshot? snapshot) {
    final colors = context.colors;
    final current = snapshot?.current;
    final olderOpen = snapshot?.olderOpen;
    final canSubmit = snapshot?.canSubmit ?? false;
    final label = olderOpen != null
        ? 'requests.types.forgotten_check_out'
        : current == null
            ? 'attendance.check_in'
            : 'attendance.check_out';
    final icon = olderOpen != null
        ? Icons.edit_calendar_rounded
        : current == null
            ? Icons.login_rounded
            : Icons.logout_rounded;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.noticeKey case final key?)
        Semantics(liveRegion: true, child: Text(key.tr())),
      if (current case AttendanceRecord(checkOut: final checkOut?))
        AppCard(
            color: context.appColors.successContainer,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.check_circle_rounded,
                    color: context.appColors.onSuccessContainer),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                    child: _homeTime(context, 'attendance.check_in',
                        current.checkIn, current.timezone)),
                SizedBox(width: AppSpacing.md),
                Expanded(
                    child: _homeTime(context, 'attendance.check_out', checkOut,
                        current.timezone)),
              ]),
              SizedBox(height: AppSpacing.sm),
              Text(current.timezone,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.appColors.onSuccessContainer)),
            ]))
      else if (current != null)
        AppCard(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(attendanceStatus(current.status),
                style: context.textTheme.titleSmall),
            SizedBox(height: AppSpacing.xs),
            Text(
                '${'attendance.check_in'.tr()}: ${attendanceTime(current.checkIn, current.timezone)}',
                style: context.textTheme.bodyMedium),
            Text(current.timezone,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ],
        )),
      if (state.data.isLoading && snapshot == null)
        const Center(child: CircularProgressIndicator()),
      if (state.data case RequestFailure(:final failure))
        Text(failure.message, style: TextStyle(color: colors.error)),
      if (canSubmit || olderOpen != null) ...[
        SizedBox(height: AppSpacing.xl),
        Center(
            child: _workProgress(
                current,
                olderOpen,
                _actionRing(
                    padding: AppSpacing.xl,
                    name: 'attendance-outer-ring',
                    expansion: 0.12,
                    color: colors.primaryContainer.withValues(alpha: 0.35),
                    child: _actionRing(
                        padding: AppSpacing.lg,
                        name: 'attendance-inner-ring',
                        expansion: 0.06,
                        color: colors.primaryContainer,
                        child: Material(
                            color: colors.primary,
                            shape: const CircleBorder(),
                            child: Semantics(
                                label: label.tr(),
                                button: true,
                                enabled: !state.busy && state.pending == null,
                                excludeSemantics: true,
                                child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTapDown: state.busy ||
                                            state.pending != null ||
                                            olderOpen != null
                                        ? null
                                        : (_) => _repelRings(),
                                    onTap: state.busy || state.pending != null
                                        ? null
                                        : olderOpen != null
                                            ? () => context.pushNamed(
                                                    'newRequest',
                                                    queryParameters: {
                                                      'attendanceId':
                                                          olderOpen.id
                                                    })
                                            : () {
                                                _repelRings();
                                                ref
                                                    .read(attendanceProvider
                                                        .notifier)
                                                    .submit();
                                              },
                                    child: SizedBox.square(
                                        dimension: 136.w,
                                        child: Center(
                                            child: state.action.isLoading
                                                ? CircularProgressIndicator(
                                                    color: colors.onPrimary)
                                                : Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                        Icon(icon,
                                                            color: colors
                                                                .onPrimary),
                                                        SizedBox(
                                                            height:
                                                                AppSpacing.xs),
                                                        Text(label.tr(),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 2,
                                                            style: context
                                                                .textTheme
                                                                .titleSmall
                                                                ?.copyWith(
                                                                    color: colors
                                                                        .onPrimary)),
                                                      ])))))))))),
        SizedBox(height: AppSpacing.lg),
        if (olderOpen != null)
          Text('attendance.older_open'
              .tr(namedArgs: {'date': olderOpen.workDate}))
        else
          Text(
              'attendance.capture_explanation'.tr(namedArgs: {
                'radius': snapshot!.policy.radiusMeters.toStringAsFixed(0),
                'accuracy':
                    snapshot.policy.maxAccuracyMeters.toStringAsFixed(0),
              }),
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
      ],
      if (state.action case RequestFailure(:final failure)) ...[
        SizedBox(height: AppSpacing.md),
        Text(failure is CaptureFailure ? failure.message.tr() : failure.message,
            style: TextStyle(color: colors.error)),
        if (failure case CaptureFailure(:final recovery)
            when recovery != CaptureRecovery.retry)
          AppButton(
              label: 'attendance.open_settings'.tr(),
              variant: ButtonVariant.outline,
              onPressed: () =>
                  ref.read(attendanceCaptureProvider).openSettings(recovery)),
      ],
    ]);
  }

  Widget _homeTime(BuildContext context, String label, DateTime value,
          String timezone) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.tr(), style: context.textTheme.bodySmall),
        Text(attendanceClock(value, timezone),
            style: context.textTheme.titleLarge),
      ]);

  Widget _workProgress(AttendanceRecord? current, AttendanceRecord? olderOpen,
          Widget child) =>
      current != null && current.checkOut == null && olderOpen == null
          ? AttendanceWorkProgress(record: current, child: child)
          : child;
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
