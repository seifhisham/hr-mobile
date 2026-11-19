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
import 'request_detail_widgets.dart';
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
  void didUpdateWidget(NewRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Opening this route again with another type (a deep link, or `go` from
    // the type picker) reuses this screen; follow the new type.
    if (oldWidget.initialType != widget.initialType &&
        requestTypes.contains(widget.initialType)) {
      setState(() {
        _type = widget.initialType!;
        _errorKey = null;
      });
    }
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

  /// Copy written for the request being made, from `requests.profiles.<type>`.
  String _profile(String field) =>
      'requests.profiles.${_type.replaceAll('-', '_')}.$field'.tr();

  /// Types that carry a short piece of guidance above the reason box.
  static const _guided = {'sick', 'urgent', 'mission', 'unpaid', 'holiday'};

  /// Types whose supporting file has a more specific name than "attachment".
  static const _namedFile = {'sick', 'mission'};

  bool _narrow(BuildContext context, double width) =>
      width < 340 || MediaQuery.textScalerOf(context).scale(1) > 1.4;

  /// Two pickers side by side, stacked when space is tight.
  Widget _pair(Widget first, Widget second) =>
      LayoutBuilder(builder: (context, box) {
        if (_narrow(context, box.maxWidth)) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            first,
            SizedBox(height: AppSpacing.md),
            second,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: first),
          SizedBox(width: AppSpacing.md),
          Expanded(child: second),
        ]);
      });

  List<Widget> _forgottenSection(RequestsState state,
      AttendanceState attendance, AttendanceRecord? record) {
    final disabled = _busy(state);
    return [
      RequestNotice(
          message: 'requests.forgotten_notice'.tr(),
          tone: RequestNoticeTone.warning),
      SizedBox(height: AppSpacing.md),
      RequestPanel(
          title: 'requests.departure_request'.tr(),
          icon: Icons.logout_rounded,
          accent: requestTypeColor(context, 'forgotten-check-out'),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (attendance.data.isLoading)
              const Center(child: CircularProgressIndicator()),
            if (attendance.data case RequestFailure(:final failure)) ...[
              RequestNotice(
                  message: failure.message, tone: RequestNoticeTone.error),
              SizedBox(height: AppSpacing.md),
            ],
            AppDropdown<String>(
                label: 'requests.open_record'.tr(),
                value: record?.id,
                enabled: !disabled,
                items: [
                  for (final open in attendance.snapshot?.records
                          .where((r) => r.checkOut == null) ??
                      <AttendanceRecord>[])
                    AppDropdownItem(
                        value: open.id,
                        label: '${open.workDate} (${open.timezone})')
                ],
                onChanged: (value) => setState(() {
                      _attendanceId = value;
                      _departureDate = null;
                      _departureTime = null;
                      _updateDeparture();
                    })),
            SizedBox(height: AppSpacing.md),
            if (record == null)
              RequestNotice(message: 'requests.open_record_required'.tr())
            else ...[
              RequestFact(
                  icon: Icons.login_rounded,
                  label: 'attendance.check_in'.tr(),
                  value: requestTime(record.checkIn, record.timezone)),
              _pair(
                  AppDatePicker(
                      label: 'requests.departure_date'.tr(),
                      hint: 'requests.choose_date'.tr(),
                      value: _departureDate,
                      enabled: !disabled,
                      onChanged: (date) => setState(() {
                            _departureDate = date;
                            _updateDeparture();
                          })),
                  AppTimePicker(
                      label: 'requests.departure_time'.tr(),
                      value: _departureTime,
                      enabled: !disabled,
                      onChanged: (time) => setState(() {
                            _departureTime = time;
                            _updateDeparture();
                          }))),
              SizedBox(height: AppSpacing.sm),
              Text(
                  'requests.timezone_notice'
                      .tr(namedArgs: {'timezone': record.timezone}),
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
              if (_instants.length > 1) ...[
                SizedBox(height: AppSpacing.md),
                RequestNotice(
                    message: 'requests.ambiguous_time'.tr(),
                    tone: RequestNoticeTone.warning),
                SizedBox(height: AppSpacing.md),
                AppDropdown<DateTime>(
                    label: 'requests.time_occurrence'.tr(),
                    value: _departure,
                    enabled: !disabled,
                    items: [
                      for (final instant in _instants)
                        AppDropdownItem(
                            value: instant,
                            label: _instantLabel(instant, record.timezone))
                    ],
                    onChanged: (time) => setState(() => _departure = time)),
              ],
            ],
          ])),
    ];
  }

  List<Widget> _datesSection(RequestsState state) {
    final accent = requestTypeColor(context, _type);
    final days = _from == null || _to == null
        ? null
        : requestDayCount(DateFormat('yyyy-MM-dd').format(_from!),
            DateFormat('yyyy-MM-dd').format(_to!));
    final backwards = _from != null && _to != null && days == null;
    return [
      RequestPanel(
          title: _profile('dates'),
          icon: Icons.date_range_outlined,
          accent: accent,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _pair(
                AppDatePicker(
                    label: 'requests.from'.tr(),
                    hint: 'requests.choose_date'.tr(),
                    value: _from,
                    enabled: !_busy(state),
                    onChanged: (date) => setState(() => _from = date)),
                AppDatePicker(
                    label: 'requests.to'.tr(),
                    hint: 'requests.choose_date'.tr(),
                    value: _to,
                    enabled: !_busy(state),
                    onChanged: (date) => setState(() => _to = date))),
            if (days != null) ...[
              SizedBox(height: AppSpacing.md),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: AppBorders.full),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ExcludeSemantics(
                            child: Icon(Icons.event_available_rounded,
                                size: 18, color: accent)),
                        SizedBox(width: AppSpacing.sm),
                        Text(requestDaysLabel(days),
                            style: context.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ]))),
            ],
            if (backwards) ...[
              SizedBox(height: AppSpacing.md),
              RequestNotice(
                  message: 'requests.range_invalid'.tr(),
                  tone: RequestNoticeTone.error),
            ],
          ])),
    ];
  }

  List<Widget> _excuseSection(AppUser? user, RequestsState state) {
    final disabled = _busy(state);
    final schedule = user?.schedule;
    return [
      RequestPanel(
          title: 'requests.excuse_details'.tr(),
          icon: Icons.more_time_rounded,
          accent: requestTypeColor(context, 'excuse'),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (schedule == null)
              RequestNotice(
                  message: 'requests.schedule_required'.tr(),
                  tone: RequestNoticeTone.warning)
            else
              RequestFact(
                  icon: Icons.schedule_rounded,
                  label: 'requests.shift'.tr(),
                  value: '${schedule.name}: ${schedule.start} – ${schedule.end}'),
            Text('requests.excuse_type'.tr(),
                style: context.textTheme.labelMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant)),
            SizedBox(height: AppSpacing.xs),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
              for (final (type, icon) in [
                ('leaving-early', Icons.logout_rounded),
                ('arriving-late', Icons.login_rounded),
                ('during-shift', Icons.schedule_rounded),
              ])
                AppChip(
                    label:
                        'requests.excuse_types.${type.replaceAll('-', '_')}'.tr(),
                    avatar: Icon(icon, size: 18),
                    selected: _excuseType == type,
                    onSelected: disabled
                        ? null
                        : (_) => setState(() => _excuseType = type)),
            ]),
            SizedBox(height: AppSpacing.md),
            AppTextField(
                label: 'requests.duration'.tr(),
                controller: _minutes,
                keyboardType: TextInputType.number,
                prefixIcon: const Icon(Icons.timelapse_rounded, size: 20),
                onChanged: (_) => setState(() {}),
                enabled: !disabled),
            SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
              for (final minutes in [15, 30, 60, 120])
                AppChip(
                    label: 'requests.minutes_short'
                        .tr(namedArgs: {'minutes': '$minutes'}),
                    selected: _minutes.text.trim() == '$minutes',
                    onSelected: disabled
                        ? null
                        : (_) => setState(() => _minutes.text = '$minutes')),
            ]),
          ])),
    ];
  }

  Widget _attachmentButton(RequestsState state) {
    final full = _attachments.length >= 3;
    final disabled = _busy(state) || full;
    return Semantics(
        button: true,
        enabled: !disabled,
        child: Material(
            color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: AppBorders.md,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: disabled ? null : _pickAttachment,
                child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Row(children: [
                      ExcludeSemantics(
                          child: Icon(Icons.attach_file_rounded,
                              color: disabled
                                  ? context.colors.onSurfaceVariant
                                  : context.colors.primary)),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                full
                                    ? 'requests.attachment_limit'.tr()
                                    : _namedFile.contains(_type)
                                        ? _profile('file')
                                        : 'requests.add_attachment'.tr(),
                                style: context.textTheme.titleSmall?.copyWith(
                                    color: disabled
                                        ? context.colors.onSurfaceVariant
                                        : context.colors.primary,
                                    fontWeight: FontWeight.w700)),
                            Text('requests.attachment_hint'.tr(),
                                style: context.textTheme.bodySmall?.copyWith(
                                    color: context.colors.onSurfaceVariant)),
                          ])),
                    ])))));
  }

  Widget _attachmentTile(int index, RequestsState state) => Padding(
      padding: EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
          padding: EdgeInsetsDirectional.only(
              start: AppSpacing.md, end: AppSpacing.xs),
          decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: AppBorders.md,
              border: Border.all(color: context.colors.outlineVariant)),
          child: Row(children: [
            ExcludeSemantics(
                child: Icon(
                    _attachments[index].mimeType == 'application/pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: context.colors.primary)),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Text(_attachments[index].name,
                    style: context.textTheme.bodyMedium)),
            AppIconButton(
                icon: Icons.close_rounded,
                size: ButtonSize.large,
                tooltip: 'requests.remove_attachment'.tr(),
                onPressed: _busy(state)
                    ? null
                    : () => setState(() => _attachments.removeAt(index))),
          ])));

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
    final gap = SizedBox(height: AppSpacing.md);
    final accent = requestTypeColor(context, _type);
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
                                RequestTypeBanner(
                                    type: _type,
                                    title: requestTypeLabel(_type),
                                    tagline: _profile('tagline')),
                                gap,
                                AppDropdown<String>(
                                    label: 'requests.type'.tr(),
                                    value: _type,
                                    enabled: !_busy(state),
                                    items: [
                                      for (final type in requestTypes)
                                        AppDropdownItem(
                                            value: type,
                                            label: requestTypeLabel(type)),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _type = value;
                                        _errorKey = null;
                                      });
                                    }),
                                gap,
                                if (_type == 'forgotten-check-out')
                                  ..._forgottenSection(state, attendance, record)
                                else ...[
                                  ..._datesSection(state),
                                  if (_type == 'excuse') ...[
                                    gap,
                                    ..._excuseSection(user, state),
                                  ],
                                ],
                                gap,
                                RequestPanel(
                                    title: 'requests.reason_files'.tr(),
                                    icon: Icons.edit_note_rounded,
                                    accent: accent,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (_guided.contains(_type)) ...[
                                            RequestNotice(
                                                message: _profile('notice')),
                                            SizedBox(height: AppSpacing.md),
                                          ],
                                          AppTextArea(
                                              label: _type == 'excuse'
                                                  ? 'requests.optional_reason'
                                                      .tr()
                                                  : _profile('reason'),
                                              hint: _profile('hint'),
                                              controller: _reason,
                                              focusNode: _reasonFocus,
                                              validator: _reasonValidator,
                                              maxLength:
                                                  _type == 'excuse' ? 120 : 500,
                                              enabled: !_busy(state)),
                                          if (_type !=
                                              'forgotten-check-out') ...[
                                            SizedBox(height: AppSpacing.sm),
                                            _attachmentButton(state),
                                            for (var index = 0;
                                                index < _attachments.length;
                                                index++)
                                              _attachmentTile(index, state),
                                          ],
                                        ])),
                                SizedBox(height: AppSpacing.lg.h),
                                if (_errorKey case final error?) ...[
                                  Semantics(
                                      liveRegion: true,
                                      child: RequestNotice(
                                          message: error.tr(),
                                          tone: RequestNoticeTone.error)),
                                  gap,
                                ],
                                RequestFeedback(state: state),
                                if (state.data
                                    case RequestFailure(:final failure)) ...[
                                  RequestNotice(
                                      message: failure.message,
                                      tone: RequestNoticeTone.error),
                                  gap,
                                ],
                                AppButton(
                                    label: 'requests.submit'.tr(),
                                    isLoading: _preparing.isLoading ||
                                        state.action.isLoading,
                                    onPressed: _busy(state) ? null : _submit),
                              ],
                            ]))))));
  }
}
