import 'dart:async';
import 'package:hrmobile/src/imports/imports.dart';
import '../../services/attendance_location_warning.dart';
import '../../services/attendance_location_source.dart';
import 'attendance_monitor_provider.dart';
import 'attendance_provider.dart';
import 'attendance_summary.dart' show attendanceTime;
import '../auth/providers/session_provider.dart';

/// App-wide monitoring survives route changes; the server alone closes attendance.
class AttendanceMonitoring extends ConsumerStatefulWidget {
  const AttendanceMonitoring({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AttendanceMonitoring> createState() =>
      _AttendanceMonitoringState();
}

class _AttendanceMonitoringState extends ConsumerState<AttendanceMonitoring>
    with WidgetsBindingObserver {
  Timer? _deadlineTimer, _clock;
  bool _enabling = false, _notificationDenied = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Remove any previous process's warning; launch reconciliation restores valid ones.
    unawaited(AttendanceLocationWarning.instance.update(null));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _deadlineChanged(ref.read(attendanceMonitorProvider));
    });
  }

  void _deadlineChanged(AttendanceMonitorState next) {
    _deadlineTimer?.cancel();
    _clock?.cancel();
    final deadline = next.location?.returnBy;
    final record = next.record;
    if (record == null || deadline == null) {
      unawaited(AttendanceLocationWarning.instance.update(null));
      return;
    }
    unawaited(AttendanceLocationWarning.instance.update(deadline,
        title: 'tracking.warning_title'.tr(),
        message: 'tracking.outside'.tr(
            namedArgs: {'time': attendanceTime(deadline, record.timezone)})));
    final remaining = deadline.difference(DateTime.now());
    _deadlineTimer =
        Timer(remaining.isNegative ? Duration.zero : remaining, () {
      unawaited(AttendanceLocationWarning.instance.update(null));
      ref.read(attendanceProvider.notifier).refresh();
      // The worker may confirm after expiry. Keep reading; never close locally.
      _deadlineTimer = Timer.periodic(const Duration(seconds: 10),
          (_) => ref.read(attendanceProvider.notifier).refresh());
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(sessionProvider).userOrNull?.employee != null) {
      ref.read(attendanceProvider.notifier).refresh().then((_) {
        if (mounted) ref.read(attendanceMonitorProvider.notifier).start();
      });
    }
  }

  Future<void> _enable() async {
    if (_enabling) return;
    setState(() => _enabling = true);
    final monitor = ref.read(attendanceMonitorProvider.notifier);
    await monitor.enable();
    if (!mounted ||
        !identical(monitor, ref.read(attendanceMonitorProvider.notifier)) ||
        ref.read(attendanceMonitorProvider).record == null) {
      return;
    }
    final allowed =
        await AttendanceLocationWarning.instance.requestPermission();
    if (mounted &&
        identical(monitor, ref.read(attendanceMonitorProvider.notifier))) {
      setState(() {
        _enabling = false;
        _notificationDenied = !allowed;
      });
      if (allowed) _deadlineChanged(ref.read(attendanceMonitorProvider));
    }
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    _clock?.cancel();
    unawaited(AttendanceLocationWarning.instance.update(null));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitor = ref.watch(attendanceMonitorProvider);
    ref.listen(attendanceMonitorProvider, (previous, next) {
      if (previous?.record?.id != next.record?.id ||
          previous?.location?.returnBy != next.location?.returnBy) {
        _deadlineChanged(next);
      }
      if (next.record == null) {
        _notificationDenied = false;
        _enabling = false;
      }
    });
    final record = monitor.record;
    if (record == null) return widget.child;
    final deadline = monitor.location?.returnBy;
    final seconds = deadline?.difference(DateTime.now()).inSeconds ?? 0;
    final remaining = seconds.clamp(0, 86400);
    final countdown =
        '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
    final failure = monitor.failure;
    return Column(children: [
      SafeArea(
          bottom: false,
          child: Material(
              color: deadline != null
                  ? context.appColors.warningContainer
                  : context.colors.surfaceContainer,
              child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: context.height * 0.4),
                  child: SingleChildScrollView(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (deadline != null)
                              Semantics(
                                  liveRegion: true,
                                  child: Text(
                                      '${'tracking.outside'.tr(namedArgs: {
                                            'time': attendanceTime(
                                                deadline, record.timezone)
                                          })} '
                                      '${seconds > 0 ? countdown : 'tracking.checking'.tr()}',
                                      style: context.textTheme.titleSmall)),
                            if (failure is NetworkFailure)
                              Text('tracking.connection'.tr(),
                                  style: TextStyle(color: context.colors.error))
                            else if (failure != null &&
                                failure is! CaptureFailure)
                              Text('tracking.reporting_failed'.tr(),
                                  style:
                                      TextStyle(color: context.colors.error)),
                            if (monitor.location?.status == 'unavailable' ||
                                failure is CaptureFailure)
                              Text('tracking.unavailable'.tr()),
                            if (failure case CaptureFailure(:final message))
                              Text(message.tr()),
                            if (monitor.policy == null)
                              Text('tracking.policy_missing'.tr())
                            else
                              AppExpansionPanel(
                                  title: 'tracking.title'.tr(),
                                  children: [
                                    Text(
                                        'tracking.explanation'.tr(namedArgs: {
                                          'interval': monitor
                                              .policy!.updateIntervalSeconds
                                              .toString(),
                                          'radius': monitor.policy!.radiusMeters
                                              .toStringAsFixed(0),
                                          'minutes':
                                              (monitor.policy!.graceSeconds /
                                                      60)
                                                  .toStringAsFixed(1),
                                        }),
                                        style: context.textTheme.bodySmall),
                                    if (_notificationDenied)
                                      Text(
                                          'tracking.notifications_denied'.tr()),
                                    Wrap(spacing: AppSpacing.sm, children: [
                                      AppTextButton(
                                          label: 'tracking.enable'.tr(),
                                          onPressed: _enabling ||
                                                  !AttendanceLocationSource
                                                      .supported
                                              ? null
                                              : _enable),
                                      AppTextButton(
                                          label:
                                              'attendance.open_settings'.tr(),
                                          onPressed: () => LocationService
                                              .instance
                                              .openLocationSettings()),
                                      AppTextButton(
                                          label: 'tracking.app_settings'.tr(),
                                          onPressed: () => openAppSettings()),
                                    ])
                                  ])
                          ]))))),
      Expanded(child: widget.child),
    ]);
  }
}
