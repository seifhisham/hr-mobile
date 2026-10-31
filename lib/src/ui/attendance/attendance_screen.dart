import 'package:hodour/src/imports/imports.dart';
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';
import 'attendance_provider.dart';
import '../../data/models/attendance_model.dart';
import 'attendance_evidence.dart';
import 'attendance_summary.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime? _from, _to;
  String? _filterStatus;

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
                          Row(children: [
                            Expanded(
                                child: Semantics(
                                    header: true,
                                    child: Text('attendance.nav_label'.tr(),
                                        style:
                                            context.textTheme.headlineMedium))),
                            const ThemeToggleButton(),
                            const NotificationButton(dotBadge: true),
                          ]),
                          SizedBox(height: AppSpacing.md),
                          const AttendanceSummary(),
                          if (snapshot != null) ...[
                            SizedBox(height: AppSpacing.lg.h),
                            Text('attendance.history'.tr(),
                                style: context.textTheme.titleLarge),
                            SizedBox(height: AppSpacing.md),
                            if (snapshot.records.isNotEmpty)
                              AppExpansionPanel(
                                  title: 'attendance.filters'.tr(),
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
                                        label: 'attendance.status_filter'.tr(),
                                        value: _filterStatus ?? '',
                                        items: [
                                          AppDropdownItem(
                                              value: '',
                                              label: 'attendance.all_statuses'
                                                  .tr()),
                                          for (final status in [
                                            'On time',
                                            'Late',
                                            'Not scheduled',
                                            'Missing check-out'
                                          ])
                                            AppDropdownItem(
                                                value: status,
                                                label: attendanceStatus(status))
                                        ],
                                        onChanged: (value) => setState(() =>
                                            _filterStatus =
                                                value == '' ? null : value)),
                                    AppTextButton(
                                        label: 'attendance.clear_filters'.tr(),
                                        onPressed: () => setState(() {
                                              _from = null;
                                              _to = null;
                                              _filterStatus = null;
                                            })),
                                  ]),
                            if (snapshot.records.isNotEmpty && records.isEmpty)
                              Text('attendance.no_matches'.tr()),
                            if (snapshot.records.isEmpty)
                              Text('attendance.no_records'.tr()),
                            for (final record in records) ...[
                              SizedBox(height: AppSpacing.md.h),
                              AppCard(
                                  title: record.workDate,
                                  subtitle: attendanceStatus(record.status),
                                  leading: Icon(Icons.event_available_outlined,
                                      color: context.colors.primary),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${'attendance.check_in'.tr()}: ${attendanceTime(record.checkIn, record.timezone)}'),
                                        Text(
                                            '${'attendance.check_out'.tr()}: ${record.checkOut == null ? 'attendance.open'.tr() : attendanceTime(record.checkOut!, record.timezone)}'),
                                        if (record.branchName case final name?)
                                          Text(name),
                                        Text(record.timezone),
                                        if (record.checkOut == null)
                                          AppTextButton(
                                              label:
                                                  'requests.types.forgotten_check_out'
                                                      .tr(),
                                              onPressed: () => context
                                                      .pushNamed('newRequest',
                                                          queryParameters: {
                                                        'attendanceId':
                                                            record.id
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
                        ])))));
  }
}
