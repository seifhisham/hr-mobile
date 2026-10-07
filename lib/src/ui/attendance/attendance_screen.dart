import 'package:hrmobile/src/imports/imports.dart';
import '../employee_navigation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'attendance_provider.dart';
import '../../data/models/attendance_model.dart';
import 'attendance_evidence.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen>
    with WidgetsBindingObserver {
  DateTime? _from, _to;
  String? _filterStatus;

  List<AttendanceRecord> _records(AttendanceSnapshot snapshot) =>
      filterAttendance(snapshot.records,
          from: _from == null ? null : DateFormat('yyyy-MM-dd').format(_from!),
          to: _to == null ? null : DateFormat('yyyy-MM-dd').format(_to!),
          status: _filterStatus);

  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addObserver(this);
    ref.read(attendanceCaptureProvider).discardLostCapture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(attendanceProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(attendanceProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceProvider);
    final snapshot = state.snapshot;
    return AppScaffold(
        bottomNavigationBar: const EmployeeNavigation(index: 1),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg.w),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmployeeHeading(
                          title: 'attendance.title'.tr(),
                          subtitle: 'design.attendance_hint'.tr(),
                          icon: Icons.access_time_rounded),
                      if (state.noticeKey case final key?)
                        Text(key.tr(), style: context.textTheme.titleMedium),
                      if (state.data case RequestFailure(:final failure))
                        Text(failure.message,
                            style: TextStyle(color: context.colors.error)),
                      if (snapshot != null) ...[
                        AppCard(
                            title: 'attendance.workday'.tr(),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(snapshot.workDate,
                                      style: context.textTheme.headlineSmall),
                                  Text(
                                      '${snapshot.schedule.name}: ${snapshot.schedule.start} – ${snapshot.schedule.end}'),
                                  SizedBox(height: AppSpacing.md.h),
                                  if (snapshot.olderOpen case final record?)
                                    Text('attendance.older_open'.tr(
                                        namedArgs: {'date': record.workDate}))
                                  else if (snapshot.current?.checkOut != null)
                                    Text('attendance.completed'.tr())
                                  else ...[
                                    Text('attendance.capture_explanation'
                                        .tr(namedArgs: {
                                      'radius': snapshot.policy.radiusMeters
                                          .toStringAsFixed(0),
                                      'accuracy': snapshot
                                          .policy.maxAccuracyMeters
                                          .toStringAsFixed(0)
                                    })),
                                    SizedBox(height: AppSpacing.md.h),
                                    AppButton(
                                        label: (snapshot.current == null
                                                ? 'attendance.check_in'
                                                : 'attendance.check_out')
                                            .tr(),
                                        isLoading: state.action.isLoading,
                                        onPressed: state.busy ||
                                                state.pending != null
                                            ? null
                                            : () => ref
                                                .read(
                                                    attendanceProvider.notifier)
                                                .submit()),
                                  ],
                                ])),
                        if (state.action
                            case RequestFailure(:final failure)) ...[
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
                                onPressed: () => ref
                                    .read(attendanceCaptureProvider)
                                    .openSettings(recovery)),
                        ],
                        SizedBox(height: AppSpacing.lg.h),
                        Text('attendance.history'.tr(),
                            style: context.textTheme.titleLarge),
                        Text('attendance.history_limit'.tr()),
                        SizedBox(height: AppSpacing.md),
                        AppDatePicker(
                            label: 'attendance.from'.tr(),
                            value: _from,
                            onChanged: (date) => setState(() {
                                  _from = date;
                                  if (_to != null && _to!.isBefore(date)) {
                                    _to = null;
                                  }
                                })),
                        SizedBox(height: AppSpacing.sm),
                        AppDatePicker(
                            label: 'attendance.to'.tr(),
                            value: _to,
                            onChanged: (date) => setState(() {
                                  _to = date;
                                  if (_from != null && _from!.isAfter(date)) {
                                    _from = null;
                                  }
                                })),
                        SizedBox(height: AppSpacing.sm),
                        AppDropdown<String>(
                            label: 'attendance.status_filter'.tr(),
                            value: _filterStatus ?? '',
                            items: [
                              AppDropdownItem(
                                  value: '',
                                  label: 'attendance.all_statuses'.tr()),
                              for (final status in [
                                'On time',
                                'Late',
                                'Not scheduled',
                                'Missing check-out'
                              ])
                                AppDropdownItem(
                                    value: status, label: _status(status))
                            ],
                            onChanged: (value) => setState(() =>
                                _filterStatus = value == '' ? null : value)),
                        AppTextButton(
                            label: 'attendance.clear_filters'.tr(),
                            onPressed: () => setState(() {
                                  _from = null;
                                  _to = null;
                                  _filterStatus = null;
                                })),
                        if (snapshot.records.isNotEmpty &&
                            _records(snapshot).isEmpty)
                          Text('attendance.no_matches'.tr()),
                        if (snapshot.records.isEmpty)
                          Text('attendance.no_records'.tr()),
                        for (final record in _records(snapshot)) ...[
                          SizedBox(height: AppSpacing.md.h),
                          AppCard(
                              title: record.workDate,
                              leading: Icon(Icons.event_available_outlined,
                                  color: context.colors.primary),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_status(record.status)),
                                    Text(
                                        '${'attendance.check_in'.tr()}: ${attendanceTime(record.checkIn, record.timezone)}'),
                                    Text(
                                        '${'attendance.check_out'.tr()}: ${record.checkOut == null ? 'attendance.open'.tr() : attendanceTime(record.checkOut!, record.timezone)}'),
                                    Text(record.timezone),
                                    if (record.checkOut == null)
                                      AppTextButton(
                                          label:
                                              'requests.types.forgotten_check_out'
                                                  .tr(),
                                          onPressed: () => context.pushNamed(
                                                  'newRequest',
                                                  queryParameters: {
                                                    'attendanceId': record.id
                                                  })),
                                    AppTextButton(
                                        label: 'attendance.evidence'.tr(),
                                        onPressed: () => showDialog<void>(
                                            context: context,
                                            builder: (_) =>
                                                AttendanceEvidenceDialog(
                                                    record: record))),
                                    Text(
                                        '${record.schedule.name}: ${record.schedule.start} – ${record.schedule.end}'),
                                  ])),
                        ],
                      ],
                      SizedBox(height: AppSpacing.lg.h),
                      AppButton(
                          label: (state.pending == null
                                  ? 'attendance.refresh'
                                  : 'attendance.reconcile')
                              .tr(),
                          variant: ButtonVariant.outline,
                          isLoading: state.data.isLoading,
                          onPressed: state.busy
                              ? null
                              : () => ref
                                  .read(attendanceProvider.notifier)
                                  .refresh()),
                    ]))));
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

String _status(String? status) => switch (status) {
      'On time' => 'attendance.on_time'.tr(),
      'Late' => 'attendance.late'.tr(),
      'Not scheduled' => 'attendance.not_scheduled'.tr(),
      'Missing check-out' => 'attendance.missing_checkout'.tr(),
      _ => status ?? '',
    };
