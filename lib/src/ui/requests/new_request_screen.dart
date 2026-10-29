import 'package:hodour/src/imports/imports.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/employee_request.dart';
import '../../data/models/attendance_model.dart';
import '../../data/models/user_model.dart';
import '../../services/request_attachment_service.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_provider.dart';
import 'requests_provider.dart';
import 'request_widgets.dart';

final requestAttachmentServiceProvider =
    Provider((ref) => RequestAttachmentService.instance);

class NewRequestScreen extends ConsumerStatefulWidget {
  const NewRequestScreen({super.key, this.attendanceId, this.initialType});
  final String? attendanceId;
  final String? initialType;
  @override
  ConsumerState<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends ConsumerState<NewRequestScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController(),
      _minutes = TextEditingController(text: '15');
  final _reasonFocus = FocusNode();
  String _type = 'leave', _excuseType = 'leaving-early';
  String? _attendanceId, _errorKey, _createdId;
  DateTime? _from, _to, _departureDate, _departure;
  TimeOfDay? _departureTime;
  List<DateTime> _instants = [];
  final List<RequestAttachment> _attachments = [];
  RequestState<void> _preparing = const RequestInitial();
  RequestSubmission? _candidate;

  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addObserver(this);
    if (requestTypes.contains(widget.initialType)) {
      _type = widget.initialType!;
    }
    if (widget.attendanceId != null) {
      _type = 'forgotten-check-out';
      _attendanceId = widget.attendanceId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(requestsProvider.notifier).clearAction();
      _refresh();
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    _minutes.dispose();
    _reasonFocus.dispose();
    _attachments.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_preparing.isLoading) _refresh();
  }

  Future<void> _refresh() async {
    await ref.read(sessionProvider.notifier).refresh();
    if (!mounted) return;
    await ref.read(attendanceProvider.notifier).refresh();
    if (!mounted) return;
    await ref.read(requestsProvider.notifier).refresh();
    _confirmCandidate();
  }

  AttendanceRecord? _record(AttendanceState attendance) =>
      attendance.snapshot?.records
          .where((r) => r.id == _attendanceId && r.checkOut == null)
          .firstOrNull;
  void _updateDeparture() {
    final record = _record(ref.read(attendanceProvider));
    _departure = null;
    _instants = [];
    if (_departureDate == null || _departureTime == null || record == null) {
      return;
    }
    try {
      _instants = departureInstants(_departureDate!, _departureTime!.hour,
          _departureTime!.minute, record.timezone);
      if (_instants.length == 1) _departure = _instants.single;
      _errorKey = _instants.isEmpty ? 'requests.nonexistent_time' : null;
    } on tz.LocationNotFoundException {
      _errorKey = 'requests.timezone_invalid';
    }
  }

  void _confirmCandidate() {
    if (!mounted || _candidate == null || _createdId != null) return;
    final action = ref.read(requestsProvider).action;
    if (action case RequestSuccess(:final data)
        when data.matches(_candidate!)) {
      setState(() {
        _createdId = data.id;
        _attachments.clear();
      });
      context.goNamed('requests');
      showGlobalToast(message: 'requests.saved'.tr(), status: 'success');
    }
  }

  String? _reasonValidator(String? value) {
    final length = value?.trim().length ?? 0;
    return length > (_type == 'excuse' ? 120 : 500) ||
            (_type != 'excuse' && length < 5)
        ? 'requests.reason_invalid'.tr()
        : null;
  }

  RequestSubmission? _submission(AppUser user) {
    if (_type == 'forgotten-check-out') {
      if (_attendanceId == null || _departure == null) {
        _errorKey = _instants.length > 1
            ? 'requests.ambiguous_time'
            : 'requests.departure_required';
        return null;
      }
      return ForgottenCheckOutRequest(
          attendanceId: _attendanceId!,
          proposedCheckOut: _departure!,
          reason: _reason.text);
    }
    if (_from == null || _to == null) {
      _errorKey = 'requests.range_invalid';
      return null;
    }
    final from = DateFormat('yyyy-MM-dd').format(_from!),
        to = DateFormat('yyyy-MM-dd').format(_to!);
    if (_type == 'excuse') {
      final minutes = int.tryParse(_minutes.text.trim());
      if (minutes == null) {
        _errorKey = 'requests.duration_invalid';
        return null;
      }
      return ExcuseRequest(
          from: from,
          to: to,
          durationMinutes: minutes,
          excuseType: _excuseType,
          shiftId: user.employee?.scheduleId ?? '',
          reason: _reason.text,
          attachments: List.of(_attachments));
    }
    return DateRangeRequest(
        type: _type,
        from: from,
        to: to,
        reason: _reason.text,
        attachments: List.of(_attachments));
  }

  Future<void> _submit() async {
    final originalUserId =
        ref.read(sessionProvider).userOrNull?.sessionIdentity;
    if (_preparing.isLoading ||
        ref.read(requestsProvider).busy ||
        ref.read(requestsProvider).pending != null) {
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) {
      _reasonFocus.requestFocus();
      return;
    }
    setState(() {
      _preparing = const RequestLoading();
      _errorKey = null;
    });
    await _refresh();
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    final user = session.userOrNull;
    if (user?.sessionIdentity != originalUserId || _createdId != null) {
      setState(() => _preparing = const RequestInitial());
      return;
    }
    final profileReady = session is SessionAuthenticated &&
        session.profileRefresh is RequestSuccess<void>;
    if (user == null ||
        !profileReady ||
        (_type == 'forgotten-check-out' &&
            ref.read(attendanceProvider).snapshot == null) ||
        ref.read(requestsProvider).data
            is! RequestSuccess<List<EmployeeRequest>>) {
      setState(() {
        _preparing = const RequestInitial();
        _errorKey = 'requests.refresh_required';
      });
      return;
    }
    final submission = _submission(user);
    final error = submission?.validate(user,
        attendance: _record(ref.read(attendanceProvider)));
    if (submission == null || error != null) {
      setState(() {
        _preparing = const RequestInitial();
        _errorKey = error ?? _errorKey;
      });
      return;
    }
    _candidate = submission;
    await ref.read(requestsProvider.notifier).submit(submission);
    if (!mounted) return;
    setState(() => _preparing = const RequestInitial());
    _confirmCandidate();
  }

  Future<void> _pickAttachment() async {
    if (_preparing.isLoading || _attachments.length >= 3) return;
    setState(() {
      _preparing = const RequestLoading();
      _errorKey = null;
    });
    final originalUserId =
        ref.read(sessionProvider).userOrNull?.sessionIdentity;
    final result = await ref.read(requestAttachmentServiceProvider).pick();
    if (!mounted) return;
    if (ref.read(sessionProvider).userOrNull?.sessionIdentity !=
        originalUserId) {
      return;
    }
    setState(() {
      _preparing = const RequestInitial();
      result.fold((_) => _errorKey = 'requests.attachment_invalid', (file) {
        if (file != null) _attachments.add(file);
      });
    });
  }

  bool _busy(RequestsState state) =>
      state.busy || state.pending != null || _preparing.isLoading;
  String _instantLabel(DateTime time, String timezone) =>
      '${requestTime(time, timezone)} · ${time.toUtc().toIso8601String()}';

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s.userOrNull?.sessionIdentity),
        (previous, next) {
      if (previous == null || previous == next) return;
      setState(() {
        _attachments.clear();
        _reason.clear();
        _candidate = null;
        _createdId = null;
        _from = null;
        _to = null;
        _departure = null;
        _departureDate = null;
        _departureTime = null;
        _attendanceId = null;
        _instants = [];
        _preparing = const RequestInitial();
      });
    });
    final state = ref.watch(requestsProvider),
        attendance = ref.watch(attendanceProvider);
    final user = ref.watch(sessionProvider).userOrNull;
    final record = _record(attendance);
    return AppScaffold(
        appBar: AppTopBar(title: 'requests.new'.tr()),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: () async {
                  if (!state.busy && !_preparing.isLoading) await _refresh();
                },
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(AppSpacing.lg.w),
                    child: Form(
                        key: _form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (user?.employee == null)
                                Text('account.no_employee'.tr())
                              else ...[
                                Text('requests.type'.tr(),
                                    style: context.textTheme.titleSmall),
                                SizedBox(height: AppSpacing.sm),
                                RequestTypeCards(
                                    selectedType: _type,
                                    onSelected: _busy(state)
                                        ? null
                                        : (value) => setState(() {
                                              _type = value;
                                              _errorKey = null;
                                            })),
                                SizedBox(height: AppSpacing.md.h),
                                if (_type == 'forgotten-check-out') ...[
                                  Text('requests.forgotten_notice'.tr(),
                                      style: context.textTheme.bodyMedium),
                                  SizedBox(height: AppSpacing.lg.h),
                                  if (attendance.data.isLoading)
                                    const Center(
                                        child: CircularProgressIndicator()),
                                  if (attendance.data
                                      case RequestFailure(:final failure))
                                    Text(failure.message),
                                  AppDropdown<String>(
                                      label: 'requests.open_record'.tr(),
                                      value: record?.id,
                                      enabled: !_busy(state),
                                      items: [
                                        for (final open in attendance
                                                .snapshot?.records
                                                .where((r) =>
                                                    r.checkOut == null) ??
                                            <AttendanceRecord>[])
                                          AppDropdownItem(
                                              value: open.id,
                                              label:
                                                  '${open.workDate} (${open.timezone})')
                                      ],
                                      onChanged: (value) => setState(() {
                                            _attendanceId = value;
                                            _departureDate = null;
                                            _departureTime = null;
                                            _updateDeparture();
                                          })),
                                  SizedBox(height: AppSpacing.md.h),
                                  if (record == null)
                                    Text('requests.open_record_required'.tr())
                                  else ...[
                                    AppCard(
                                      color: context.colors.surface,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                              '${'attendance.check_in'.tr()}: ${requestTime(record.checkIn, record.timezone)}',
                                              style:
                                                  context.textTheme.titleSmall),
                                          SizedBox(height: AppSpacing.sm.h),
                                          Text(
                                              'requests.timezone_notice'.tr(
                                                  namedArgs: {
                                                    'timezone': record.timezone
                                                  }),
                                              style: context.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: context.colors
                                                          .onSurfaceVariant)),
                                          SizedBox(height: AppSpacing.lg.h),
                                          AppDatePicker(
                                              label: 'requests.departure_date'
                                                  .tr(),
                                              hint: 'requests.choose_date'.tr(),
                                              value: _departureDate,
                                              enabled: !_busy(state),
                                              onChanged: (date) => setState(() {
                                                    _departureDate = date;
                                                    _updateDeparture();
                                                  })),
                                          SizedBox(height: AppSpacing.md.h),
                                          AppTimePicker(
                                              label: 'requests.departure_time'
                                                  .tr(),
                                              value: _departureTime,
                                              enabled: !_busy(state),
                                              onChanged: (time) => setState(() {
                                                    _departureTime = time;
                                                    _updateDeparture();
                                                  })),
                                        ],
                                      ),
                                    ),
                                    if (_instants.length > 1) ...[
                                      SizedBox(height: AppSpacing.md.h),
                                      Text('requests.ambiguous_time'.tr()),
                                      AppDropdown<DateTime>(
                                          label:
                                              'requests.time_occurrence'.tr(),
                                          value: _departure,
                                          enabled: !_busy(state),
                                          items: [
                                            for (final instant in _instants)
                                              AppDropdownItem(
                                                  value: instant,
                                                  label: _instantLabel(
                                                      instant, record.timezone))
                                          ],
                                          onChanged: (time) => setState(
                                              () => _departure = time)),
                                    ],
                                  ],
                                ] else ...[
                                  AppCard(
                                    color: context.colors.surface,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        AppDatePicker(
                                            label: 'requests.from'.tr(),
                                            hint: 'requests.choose_date'.tr(),
                                            value: _from,
                                            enabled: !_busy(state),
                                            onChanged: (date) =>
                                                setState(() => _from = date)),
                                        SizedBox(height: AppSpacing.md.h),
                                        AppDatePicker(
                                            label: 'requests.to'.tr(),
                                            hint: 'requests.choose_date'.tr(),
                                            value: _to,
                                            enabled: !_busy(state),
                                            onChanged: (date) =>
                                                setState(() => _to = date)),
                                      ],
                                    ),
                                  ),
                                  if (_type == 'excuse') ...[
                                    SizedBox(height: AppSpacing.md.h),
                                    Text(user!.schedule == null
                                        ? 'requests.schedule_required'.tr()
                                        : '${user.schedule!.name}: ${user.schedule!.start} – ${user.schedule!.end}'),
                                    AppTextField(
                                        label: 'requests.duration'.tr(),
                                        controller: _minutes,
                                        keyboardType: TextInputType.number,
                                        enabled: !_busy(state)),
                                    AppDropdown<String>(
                                        label: 'requests.excuse_type'.tr(),
                                        value: _excuseType,
                                        enabled: !_busy(state),
                                        items: [
                                          for (final type in excuseTypes)
                                            AppDropdownItem(
                                                value: type,
                                                label:
                                                    'requests.excuse_types.${type.replaceAll('-', '_')}'
                                                        .tr())
                                        ],
                                        onChanged: (value) => setState(
                                            () => _excuseType = value!)),
                                  ],
                                  SizedBox(height: AppSpacing.md.h),
                                  Text('requests.deduction_policy'.tr(),
                                      style: context.textTheme.bodySmall
                                          ?.copyWith(
                                              color: context
                                                  .colors.onSurfaceVariant)),
                                ],
                                SizedBox(height: AppSpacing.md.h),
                                AppTextArea(
                                    label: (_type == 'excuse'
                                            ? 'requests.optional_reason'
                                            : 'requests.reason')
                                        .tr(),
                                    controller: _reason,
                                    focusNode: _reasonFocus,
                                    validator: _reasonValidator,
                                    maxLength: _type == 'excuse' ? 120 : 500,
                                    enabled: !_busy(state)),
                                if (_type != 'forgotten-check-out') ...[
                                  SizedBox(height: AppSpacing.md.h),
                                  Semantics(
                                      button: true,
                                      enabled: !_busy(state) &&
                                          _attachments.length < 3,
                                      child: AppCard(
                                          color: context
                                              .colors.surfaceContainerLow,
                                          onTap: _busy(state) ||
                                                  _attachments.length >= 3
                                              ? null
                                              : _pickAttachment,
                                          padding:
                                              EdgeInsets.all(AppSpacing.lg),
                                          child: SizedBox(
                                              width: double.infinity,
                                              child: Column(children: [
                                                ExcludeSemantics(
                                                    child: Container(
                                                        padding: EdgeInsets.all(
                                                            AppSpacing.md),
                                                        decoration: BoxDecoration(
                                                            color: context
                                                                .colors
                                                                .primaryContainer,
                                                            borderRadius:
                                                                AppBorders
                                                                    .full),
                                                        child: Icon(
                                                            Icons
                                                                .upload_file_outlined,
                                                            size: AppSpacing.xl,
                                                            color: context
                                                                .colors
                                                                .onPrimaryContainer))),
                                                SizedBox(height: AppSpacing.md),
                                                Text(
                                                    (_attachments.length >= 3
                                                            ? 'requests.attachment_limit'
                                                            : 'requests.add_attachment')
                                                        .tr(),
                                                    textAlign: TextAlign.center,
                                                    style: context
                                                        .textTheme.titleMedium
                                                        ?.copyWith(
                                                            color: _busy(
                                                                        state) ||
                                                                    _attachments
                                                                            .length >=
                                                                        3
                                                                ? context.colors
                                                                    .onSurfaceVariant
                                                                : context.colors
                                                                    .primary)),
                                                SizedBox(height: AppSpacing.sm),
                                                Text(
                                                    'requests.attachment_hint'
                                                        .tr(),
                                                    textAlign: TextAlign.center,
                                                    style: context
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                            color: context
                                                                .colors
                                                                .onSurfaceVariant)),
                                              ])))),
                                  for (var index = 0;
                                      index < _attachments.length;
                                      index++)
                                    Padding(
                                        padding:
                                            EdgeInsets.only(top: AppSpacing.sm),
                                        child: AppCard(
                                            child: Row(children: [
                                          ExcludeSemantics(
                                              child: Icon(
                                                  _attachments[index]
                                                              .mimeType ==
                                                          'application/pdf'
                                                      ? Icons
                                                          .picture_as_pdf_outlined
                                                      : Icons.image_outlined,
                                                  color:
                                                      context.colors.primary)),
                                          SizedBox(width: AppSpacing.md),
                                          Expanded(
                                              child: Text(
                                                  _attachments[index].name,
                                                  style: context
                                                      .textTheme.bodyMedium)),
                                          AppIconButton(
                                              icon: Icons.close_rounded,
                                              size: ButtonSize.large,
                                              tooltip:
                                                  'requests.remove_attachment'
                                                      .tr(),
                                              onPressed: _busy(state)
                                                  ? null
                                                  : () => setState(() =>
                                                      _attachments
                                                          .removeAt(index))),
                                        ]))),
                                ],
                                SizedBox(height: AppSpacing.lg.h),
                                if (_errorKey case final error?)
                                  Semantics(
                                      liveRegion: true,
                                      child: Text(error.tr(),
                                          style: TextStyle(
                                              color: context.colors.error))),
                                RequestFeedback(state: state),
                                if (state.data
                                    case RequestFailure(:final failure))
                                  Text(failure.message),
                                AppButton(
                                    label: 'requests.submit'.tr(),
                                    isLoading: _preparing.isLoading ||
                                        state.action.isLoading,
                                    onPressed: _busy(state) ? null : _submit),
                              ],
                            ]))))));
  }
}
