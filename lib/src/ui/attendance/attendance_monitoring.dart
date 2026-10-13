import 'dart:async';
import 'package:hrmobile/src/imports/imports.dart';
import '../../services/attendance_location_source.dart';
import '../../services/attendance_location_warning.dart';
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
  late final AttendanceLocationWarning _warning;
  RequestState<void> _enableAction = const RequestInitial();
  bool _notificationDenied = false, _detailsOpen = false;
  bool? _backgroundAllowed;
  @override
  void initState() {
    super.initState();
    _warning = ref.read(attendanceLocationWarningProvider);
    WidgetsBinding.instance.addObserver(this);
    // Remove any previous process's warning; launch reconciliation restores valid ones.
    unawaited(_warning.update(null));
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
      unawaited(_warning.update(null));
      return;
    }
    unawaited(_warning.update(deadline,
        title: 'tracking.warning_title'.tr(),
        message: 'tracking.outside'.tr(
            namedArgs: {'time': attendanceTime(deadline, record.timezone)})));
    final remaining = deadline.difference(DateTime.now());
    _deadlineTimer =
        Timer(remaining.isNegative ? Duration.zero : remaining, () {
      unawaited(_warning.update(null));
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
    if (_enableAction.isLoading) return;
    // Distinct attempts prevent late completions from overwriting a newer request.
    // ignore: prefer_const_constructors
    final action = RequestLoading<void>();
    setState(() {
      _enableAction = action;
      _backgroundAllowed = null;
      _notificationDenied = false;
    });
    final monitor = ref.read(attendanceMonitorProvider.notifier);
    final recordId = ref.read(attendanceMonitorProvider).record?.id;
    bool isCurrent() =>
        mounted &&
        identical(_enableAction, action) &&
        identical(monitor, ref.read(attendanceMonitorProvider.notifier)) &&
        ref.read(attendanceMonitorProvider).record?.id == recordId;
    try {
      await monitor.enable();
      if (!isCurrent()) return;
      final background = await ref
          .read(attendanceLocationSourceProvider)
          .hasBackgroundAccess();
      if (!isCurrent()) return;
      final notifications = await _warning.requestPermission();
      if (!isCurrent()) return;
      setState(() {
        _backgroundAllowed = background;
        _notificationDenied = !notifications;
        _enableAction = const RequestSuccess(null);
      });
      if (notifications) _deadlineChanged(ref.read(attendanceMonitorProvider));
    } catch (error) {
      if (isCurrent()) {
        setState(
            () => _enableAction = RequestFailure(Failure.fromException(error)));
      }
    } finally {
      if (mounted && identical(_enableAction, action)) {
        setState(() => _enableAction = const RequestInitial());
      }
    }
  }

  String _setupError(Failure failure) => switch (failure) {
        CaptureFailure(:final message) => message.tr(),
        NetworkFailure() => 'tracking.connection'.tr(),
        _ => 'tracking.reporting_failed'.tr(),
      };

  Future<void> _showDetails() async {
    if (_detailsOpen) {
      return;
    }
    final navigatorContext = rootContext;
    if (navigatorContext == null) {
      return;
    }
    setState(() => _detailsOpen = true);
    try {
      await showModalBottomSheet<void>(
        barrierColor: context.colors.scrim.withValues(alpha: 0.54),
        context: navigatorContext,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: AppBorders.xl),
        clipBehavior: Clip.antiAlias,
        builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, updateSheet) => Consumer(
                  builder: (context, ref, _) {
                    final monitor = ref.watch(attendanceMonitorProvider);
                    final policy = monitor.policy;
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.85),
                      child: SingleChildScrollView(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Semantics(
                                          header: true,
                                          child: Text('tracking.details'.tr(),
                                              style: context
                                                  .textTheme.titleLarge
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600)))),
                                  AppIconButton(
                                      icon: Icons.close,
                                      tooltip: 'requests.close'.tr(),
                                      onPressed: () =>
                                          Navigator.of(sheetContext).pop()),
                                ]),
                                SizedBox(height: AppSpacing.md),
                                if (monitor.record == null)
                                  Text('tracking.stopped'.tr())
                                else ...[
                                  _detail(
                                      context,
                                      Icons.privacy_tip_outlined,
                                      'tracking.privacy_title',
                                      'tracking.background_notice'.tr()),
                                  if (policy == null)
                                    Text('tracking.policy_missing'.tr())
                                  else ...[
                                    _detail(
                                        context,
                                        Icons.update_rounded,
                                        'tracking.updates_title',
                                        'tracking.updates_hint'.tr(namedArgs: {
                                          'interval':
                                              '${policy.updateIntervalSeconds}'
                                        })),
                                    _detail(
                                        context,
                                        Icons.location_off_outlined,
                                        'tracking.return_title',
                                        'tracking.return_hint'.tr(namedArgs: {
                                          'radius': policy.radiusMeters
                                              .toStringAsFixed(0),
                                          'minutes': (policy.graceSeconds / 60)
                                              .toStringAsFixed(1),
                                        })),
                                    _detail(
                                        context,
                                        Icons.settings_outlined,
                                        'tracking.permissions_title',
                                        'tracking.permissions_hint'.tr()),
                                    if (!AttendanceLocationSource.supported)
                                      Text('tracking.phone_only'.tr()),
                                    if (_enableAction.isLoading ||
                                        _enableAction
                                            is! RequestInitial<void> ||
                                        monitor.failure != null)
                                      Semantics(
                                          liveRegion: true,
                                          child: AppCard(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                if (_enableAction.isLoading)
                                                  Text(
                                                      'tracking.enabling'.tr()),
                                                if (monitor.failure
                                                    case final failure?)
                                                  Text(_setupError(failure),
                                                      style: context
                                                          .textTheme.bodyMedium
                                                          ?.copyWith(
                                                              color: context
                                                                  .colors
                                                                  .error)),
                                                if (_enableAction
                                                    case RequestFailure(
                                                      :final failure
                                                    ))
                                                  Text(_setupError(failure),
                                                      style: context
                                                          .textTheme.bodyMedium
                                                          ?.copyWith(
                                                              color: context
                                                                  .colors
                                                                  .error)),
                                                if (_enableAction
                                                    is RequestSuccess<
                                                        void>) ...[
                                                  _permissionResult(
                                                      context,
                                                      _backgroundAllowed ??
                                                          false,
                                                      'tracking.background_enabled',
                                                      'tracking.background_needed'),
                                                  SizedBox(
                                                      height: AppSpacing.sm),
                                                  _permissionResult(
                                                      context,
                                                      !_notificationDenied,
                                                      'tracking.notifications_enabled',
                                                      'tracking.notifications_denied'),
                                                ],
                                              ]))),
                                    SizedBox(height: AppSpacing.md),
                                    AppButton(
                                        label: 'tracking.enable'.tr(),
                                        prefixIcon: const ExcludeSemantics(
                                            child: Icon(
                                                Icons.location_on_outlined)),
                                        isLoading: _enableAction.isLoading,
                                        onPressed: _enableAction.isLoading ||
                                                !AttendanceLocationSource
                                                    .supported
                                            ? null
                                            : () async {
                                                final pending = _enable();
                                                updateSheet(() {});
                                                await pending;
                                                if (sheetContext.mounted) {
                                                  updateSheet(() {});
                                                }
                                              }),
                                    SizedBox(height: AppSpacing.sm),
                                    AppButton(
                                        label: 'attendance.open_settings'.tr(),
                                        variant: ButtonVariant.outline,
                                        prefixIcon: const ExcludeSemantics(
                                            child: Icon(
                                                Icons.my_location_outlined)),
                                        onPressed: () => LocationService
                                            .instance
                                            .openLocationSettings()),
                                    SizedBox(height: AppSpacing.sm),
                                    AppButton(
                                        label: 'tracking.app_settings'.tr(),
                                        variant: ButtonVariant.outline,
                                        prefixIcon: const ExcludeSemantics(
                                            child:
                                                Icon(Icons.settings_outlined)),
                                        onPressed: () => openAppSettings()),
                                  ],
                                ],
                              ])),
                    );
                  },
                )),
      );
    } finally {
      if (mounted) {
        setState(() => _detailsOpen = false);
      }
    }
  }

  Widget _permissionResult(BuildContext context, bool allowed, String success,
          String required) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
            child: Icon(
                allowed
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color:
                    allowed ? context.colors.primary : context.colors.error)),
        SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text((allowed ? success : required).tr(),
                style: context.textTheme.bodyMedium)),
      ]);

  Widget _detail(
          BuildContext context, IconData icon, String title, String body) =>
      Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.lg),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Icon(icon, color: context.colors.primary)),
          SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title.tr(),
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: AppSpacing.xs),
                Text(body, style: context.textTheme.bodyMedium),
              ])),
        ]),
      );

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    _clock?.cancel();
    unawaited(_warning.update(null));
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
        _enableAction = const RequestInitial();
        _backgroundAllowed = null;
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
      IgnorePointer(
          ignoring: _detailsOpen,
          child: ExcludeSemantics(
              excluding: _detailsOpen,
              child: Container(
                  color: context.colors.surface,
                  foregroundDecoration: BoxDecoration(
                      color: _detailsOpen
                          ? context.colors.scrim.withValues(alpha: 0.54)
                          : Colors.transparent),
                  child: SafeArea(
                      bottom: false,
                      child: Material(
                          color: deadline != null
                              ? context.appColors.warningContainer
                              : context.colors.surface,
                          child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxHeight: context.height * 0.4),
                              child: SingleChildScrollView(
                                  padding: EdgeInsets.fromLTRB(AppSpacing.lg,
                                      AppSpacing.sm, AppSpacing.lg, 0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Semantics(
                                            button: true,
                                            child: AppCard(
                                                color: context
                                                    .colors.surfaceContainerLow,
                                                onTap: _showDetails,
                                                padding: EdgeInsets.all(
                                                    AppSpacing.md),
                                                child: Row(children: [
                                                  ExcludeSemantics(
                                                      child: Container(
                                                          padding: EdgeInsets.all(
                                                              AppSpacing.ms),
                                                          decoration: BoxDecoration(
                                                              color: deadline != null
                                                                  ? context
                                                                      .appColors
                                                                      .warningContainer
                                                                  : context
                                                                      .colors
                                                                      .primaryContainer,
                                                              borderRadius:
                                                                  AppBorders
                                                                      .lg),
                                                          child: Icon(deadline != null ? Icons.location_off_outlined : Icons.location_on_rounded,
                                                              color: deadline != null
                                                                  ? context
                                                                      .appColors
                                                                      .onWarningContainer
                                                                  : context
                                                                      .colors
                                                                      .onPrimaryContainer))),
                                                  SizedBox(
                                                      width: AppSpacing.md),
                                                  Expanded(
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                        Text(
                                                            (monitor.location?.status ==
                                                                            'inside' &&
                                                                        failure ==
                                                                            null
                                                                    ? 'tracking.at_office'
                                                                    : 'tracking.title')
                                                                .tr(),
                                                            style: context
                                                                .textTheme
                                                                .titleSmall
                                                                ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600)),
                                                        SizedBox(
                                                            height:
                                                                AppSpacing.xs),
                                                        Text(
                                                            'tracking.details'
                                                                .tr(),
                                                            style: context
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                    color: context
                                                                        .colors
                                                                        .primary)),
                                                      ])),
                                                  SizedBox(
                                                      width: AppSpacing.sm),
                                                  ExcludeSemantics(
                                                      child: Icon(
                                                          Directionality.of(
                                                                      context) ==
                                                                  TextDirection
                                                                      .rtl
                                                              ? Icons
                                                                  .chevron_left_rounded
                                                              : Icons
                                                                  .chevron_right_rounded,
                                                          color: context.colors
                                                              .onSurfaceVariant)),
                                                ]))),
                                        if (deadline != null ||
                                            failure != null ||
                                            monitor.location?.status ==
                                                'unavailable' ||
                                            monitor.policy == null)
                                          SizedBox(height: AppSpacing.md),
                                        if (deadline != null)
                                          Semantics(
                                              liveRegion: true,
                                              child: Text(
                                                  '${'tracking.outside'.tr(namedArgs: {
                                                        'time': attendanceTime(
                                                            deadline,
                                                            record.timezone)
                                                      })} '
                                                  '${seconds > 0 ? countdown : 'tracking.checking'.tr()}',
                                                  style: context
                                                      .textTheme.titleSmall)),
                                        if (failure is NetworkFailure)
                                          Text('tracking.connection'.tr(),
                                              style: TextStyle(
                                                  color: context.colors.error))
                                        else if (failure != null &&
                                            failure is! CaptureFailure)
                                          Text('tracking.reporting_failed'.tr(),
                                              style: TextStyle(
                                                  color: context.colors.error)),
                                        if (monitor.location?.status ==
                                                'unavailable' ||
                                            failure is CaptureFailure)
                                          Text('tracking.unavailable'.tr()),
                                        if (failure
                                            case CaptureFailure(:final message))
                                          Text(message.tr()),
                                        if (monitor.policy == null)
                                          Text('tracking.policy_missing'.tr()),
                                      ])))))))),
      Expanded(
          child: MediaQuery.removePadding(
              context: context, removeTop: true, child: widget.child)),
    ]);
  }
}
