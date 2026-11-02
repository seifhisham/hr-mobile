import 'package:hodour/src/imports/imports.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';
import 'attendance_provider.dart';
import '../../data/models/attendance_model.dart';
import 'attendance_evidence.dart';
import 'attendance_record_widgets.dart';
import 'attendance_overview.dart';
import '../../data/models/attendance_totals.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen>
    with WidgetsBindingObserver {
  DateTime? _from, _to;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(attendanceProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(attendanceProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<AttendanceRecord> _records(AttendanceSnapshot snapshot) =>
      filterAttendance(snapshot.records,
          from: _from == null ? null : DateFormat('yyyy-MM-dd').format(_from!),
          to: _to == null ? null : DateFormat('yyyy-MM-dd').format(_to!),
          status: _filterStatus);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceProvider);
    final snapshot = state.snapshot;
    final records =
        snapshot == null ? <AttendanceRecord>[] : _records(snapshot);
    return AppScaffold(
        body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
                onRefresh: () async {
                  if (!state.busy) {
                    await ref.read(attendanceProvider.notifier).refresh();
                  }
                },
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(AppSpacing.lg.w).copyWith(
                        bottom: AppSpacing.lg.w +
                            MediaQuery.paddingOf(context).bottom),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppCard(
                              color: context.appColors.homeBlue,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Semantics(
                                              header: true,
                                              child: Text(
                                                  'attendance.nav_label'.tr(),
                                                  style: context
                                                      .textTheme.headlineMedium
                                                      ?.copyWith(
                                                          color: context
                                                              .appColors
                                                              .onHomeBlue,
                                                          fontWeight: FontWeight
                                                              .w700)))),
                                      ThemeToggleButton(
                                          color: context.appColors.onHomeBlue),
                                      NotificationButton(
                                          dotBadge: true,
                                          color: context.appColors.onHomeBlue),
                                    ]),
                                    if (snapshot != null)
                                      AttendanceOverview(
                                          totals: AttendanceTotals.fromRecords(
                                              records),
                                          filtered: _from != null ||
                                              _to != null ||
                                              _filterStatus != null),
                                  ])),
                          SizedBox(height: AppSpacing.md),
                          if (state.data.isLoading && snapshot == null)
                            const Center(child: CircularProgressIndicator()),
                          if (state.noticeKey case final key?)
                            Semantics(liveRegion: true, child: Text(key.tr())),
                          if (state.data case RequestFailure(:final failure))
                            Text(failure.message,
                                style: TextStyle(color: context.colors.error)),
                          if (state.pending != null ||
                              state.data is RequestFailure)
                            AppButton(
                                label: (state.pending != null
                                        ? 'attendance.reconcile'
                                        : 'attendance.refresh')
                                    .tr(),
                                variant: ButtonVariant.outline,
                                onPressed: state.busy
                                    ? null
                                    : () => ref
                                        .read(attendanceProvider.notifier)
                                        .refresh()),
                          if (snapshot != null) ...[
                            SizedBox(height: AppSpacing.lg.h),
                            Semantics(
                                header: true,
                                child: Text('attendance.history'.tr(),
                                    style: context.textTheme.titleLarge)),
                            SizedBox(height: AppSpacing.md),
                            if (snapshot.records.isNotEmpty)
                              AppCard(
                                  color: context.colors.surface,
                                  padding: EdgeInsets.zero,
                                  child: ExpansionTile(
                                      tilePadding: EdgeInsets.symmetric(
                                          horizontal: AppSpacing.md,
                                          vertical: AppSpacing.sm),
                                      childrenPadding: EdgeInsets.fromLTRB(
                                          AppSpacing.md,
                                          AppSpacing.sm,
                                          AppSpacing.md,
                                          AppSpacing.md),
                                      shape: const Border(),
                                      collapsedShape: const Border(),
                                      iconColor: context.colors.primary,
                                      collapsedIconColor:
                                          context.colors.primary,
                                      textColor: context.colors.onSurface,
                                      collapsedTextColor:
                                          context.colors.onSurface,
                                      expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                                          ? AnimationStyle.noAnimation
                                          : const AnimationStyle(
                                              duration: AppDurations.normal,
                                              curve: AppCurves.standard),
                                      leading: ExcludeSemantics(
                                          child: Container(
                                              padding:
                                                  EdgeInsets.all(AppSpacing.sm),
                                              decoration: BoxDecoration(
                                                  color: context
                                                      .colors.primaryContainer,
                                                  borderRadius: AppBorders.md),
                                              child: Icon(Icons.tune_rounded,
                                                  color: context.colors
                                                      .onPrimaryContainer))),
                                      title: Text('attendance.filters'.tr(),
                                          style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                      children: [
                                        AppDatePicker(
                                            label: 'attendance.from'.tr(),
                                            value: _from,
                                            onChanged: (date) => setState(() {
                                                  _from = date;
                                                  if (_to != null &&
                                                      _to!.isBefore(date)) {
                                                    _to = null;
                                                  }
                                                })),
                                        SizedBox(height: AppSpacing.sm),
                                        AppDatePicker(
                                            label: 'attendance.to'.tr(),
                                            value: _to,
                                            onChanged: (date) => setState(() {
                                                  _to = date;
                                                  if (_from != null &&
                                                      _from!.isAfter(date)) {
                                                    _from = null;
                                                  }
                                                })),
                                        SizedBox(height: AppSpacing.sm),
                                        AppDropdown<String>(
                                            label:
                                                'attendance.status_filter'.tr(),
                                            value: _filterStatus ?? '',
                                            items: [
                                              AppDropdownItem(
                                                  value: '',
                                                  label:
                                                      'attendance.all_statuses'
                                                          .tr()),
                                              for (final status in [
                                                'On time',
                                                'Late',
                                                'Not scheduled',
                                                'Missing check-out'
                                              ])
                                                AppDropdownItem(
                                                    value: status,
                                                    label: attendanceStatus(
                                                        status))
                                            ],
                                            onChanged: (value) => setState(() =>
                                                _filterStatus = value == ''
                                                    ? null
                                                    : value)),
                                        AppTextButton(
                                            label:
                                                'attendance.clear_filters'.tr(),
                                            onPressed: () => setState(() {
                                                  _from = null;
                                                  _to = null;
                                                  _filterStatus = null;
                                                })),
                                      ])),
                            SizedBox(height: AppSpacing.md),
                            if (snapshot.records.isNotEmpty && records.isEmpty)
                              Text('attendance.no_matches'.tr()),
                            if (snapshot.records.isEmpty)
                              Text('attendance.no_records'.tr()),
                            for (final record in records) ...[
                              SizedBox(height: AppSpacing.md.h),
                              AppCard(
                                  key: ValueKey(record.id),
                                  color: context.colors.surface,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                  child: Text(record.workDate,
                                                      style: context
                                                          .textTheme.titleMedium
                                                          ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700))),
                                              SizedBox(width: AppSpacing.sm),
                                              Flexible(
                                                  child: Container(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              horizontal:
                                                                  AppSpacing.sm,
                                                              vertical:
                                                                  AppSpacing
                                                                      .xs),
                                                      decoration: BoxDecoration(
                                                          color: switch (
                                                              record.status) {
                                                            'On time' => context
                                                                .appColors
                                                                .successContainer,
                                                            'Late' => context
                                                                .appColors
                                                                .warningContainer,
                                                            'Missing check-out' =>
                                                              context.colors
                                                                  .errorContainer,
                                                            _ => context.colors
                                                                .secondaryContainer,
                                                          },
                                                          borderRadius:
                                                              AppBorders.full),
                                                      child: Text(
                                                          attendanceStatus(
                                                              record.status),
                                                          style: context
                                                              .textTheme
                                                              .labelMedium
                                                              ?.copyWith(
                                                                  color: switch (
                                                                      record
                                                                          .status) {
                                                            'On time' => context
                                                                .appColors
                                                                .onSuccessContainer,
                                                            'Late' => context
                                                                .appColors
                                                                .onWarningContainer,
                                                            'Missing check-out' =>
                                                              context.colors
                                                                  .onErrorContainer,
                                                            _ => context.colors
                                                                .onSecondaryContainer,
                                                          })))),
                                            ]),
                                        SizedBox(height: AppSpacing.lg),
                                        AttendanceTimePair(record: record),
                                        if (record.checkOut == null &&
                                            (record.workDate.compareTo(snapshot.workDate) < 0 ||
                                                record.status ==
                                                    'Missing check-out'))
                                          if (snapshot.hasPendingForgottenCheckout(record))
                                            Padding(
                                                padding: EdgeInsets.only(
                                                    top: AppSpacing.sm),
                                                child: Text('attendance.correction_pending'.tr(),
                                                    style: context.textTheme.bodyMedium
                                                        ?.copyWith(
                                                            color: context
                                                                .colors
                                                                .primary)))
                                          else
                                            AppTextButton(
                                                label: 'requests.types.forgotten_check_out'
                                                    .tr(),
                                                onPressed: () => context.pushNamed(
                                                    'newRequest',
                                                    queryParameters: {'attendanceId': record.id})),
                                        SizedBox(height: AppSpacing.sm),
                                        AppExpansionPanel(
                                            title: 'attendance.record_details'
                                                .tr(),
                                            children: [
                                              Text(
                                                  '${'attendance.arrival'.tr()}: ${attendanceTime(record.checkIn, record.timezone)}'),
                                              if (record.checkOut
                                                  case final checkOut?)
                                                Text(
                                                    '${'attendance.departure'.tr()}: ${attendanceTime(checkOut, record.timezone)}'),
                                              if (record.branchName
                                                  case final name?)
                                                Text(name),
                                              Text(
                                                  '${record.schedule.name}: ${record.schedule.start} – ${record.schedule.end}'),
                                              AppTextButton(
                                                  label: 'attendance.evidence'
                                                      .tr(),
                                                  onPressed: () => showDialog<
                                                          void>(
                                                      context: context,
                                                      builder: (_) =>
                                                          AttendanceEvidenceDialog(
                                                              record: record))),
                                            ]),
                                      ])),
                            ],
                          ],
                        ])))));
  }
}
