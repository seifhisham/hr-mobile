import 'package:hodour/src/imports/imports.dart';
import 'request_detail_widgets.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import '../auth/providers/session_provider.dart';
import '../../data/models/employee_request.dart';
import 'requests_provider.dart';
import 'request_widgets.dart';
import '../notifications/notifications_provider.dart';

class RequestDetailsScreen extends ConsumerStatefulWidget {
  const RequestDetailsScreen(
      {super.key, required this.id, this.managed = false, this.sheet = false});
  final String id;
  final bool managed;
  final bool sheet;
  @override
  ConsumerState<RequestDetailsScreen> createState() =>
      _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends ConsumerState<RequestDetailsScreen>
    with WidgetsBindingObserver {
  StateNotifierProvider<RequestsController, RequestsState> get _provider =>
      widget.managed ? managedRequestsProvider : requestsProvider;
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(_provider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(_provider.notifier).refresh();
    }
  }

  Future<void> _withdraw(EmployeeRequest item) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('requests.withdraw'.tr()),
                content: Text('requests.withdraw_confirmation'.tr()),
                actions: [
                  AppTextButton(
                      label: 'requests.cancel'.tr(),
                      onPressed: () => Navigator.of(context).pop(false)),
                  AppTextButton(
                      label: 'requests.withdraw'.tr(),
                      onPressed: () => Navigator.of(context).pop(true)),
                ]));
    if (confirmed != true || !mounted) return;
    await ref.read(_provider.notifier).withdraw(item, _reason.text);
  }

  Future<void> _review(EmployeeRequest item, String status) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await ref.read(_provider.notifier).review(item, status, _reason.text);
    if (mounted) {
      await ref
          .read(notificationsProvider.notifier)
          .refresh(afterMutation: true);
    }
  }

  String? _validateReason(String? value) =>
      (value?.trim().length ?? 0) < 5 || (value?.trim().length ?? 0) > 500
          ? (widget.managed
                  ? 'requests.review_reason_invalid'
                  : 'requests.reason_invalid')
              .tr()
          : null;
  List<Widget> _information(EmployeeRequest item) {
    final attendance = item.attendance;
    return [
      if (item.from != null)
        RequestFact(
            icon: Icons.date_range_outlined,
            label: 'requests.dates'.tr(),
            value: '${item.from} – ${item.to}'),
      if (item.durationMinutes != null)
        RequestFact(
            icon: Icons.timelapse_rounded,
            label: 'requests.duration_label'.tr(),
            value: 'requests.minutes_per_day'
                .tr(namedArgs: {'minutes': '${item.durationMinutes}'})),
      if (item.excuseType != null)
        RequestFact(
            icon: Icons.more_time_rounded,
            label: 'requests.excuse_type'.tr(),
            value:
                'requests.excuse_types.${item.excuseType!.replaceAll('-', '_')}'
                    .tr()),
      if (item.shiftId != null)
        RequestFact(
            icon: Icons.schedule_rounded,
            label: 'requests.shift'.tr(),
            value: 'requests.assigned_shift'.tr()),
      if (attendance != null) ...[
        RequestFact(
            icon: Icons.event_note_outlined,
            label: 'requests.workday'.tr(),
            value: '${attendance.workDate} · ${attendance.timezone}'),
        RequestFact(
            icon: Icons.login_rounded,
            label: 'attendance.check_in'.tr(),
            value: requestTime(attendance.checkIn, attendance.timezone)),
        if (item.proposedCheckOut case final departure?)
          RequestFact(
              icon: Icons.logout_rounded,
              label: 'requests.proposed_departure'.tr(),
              value: requestTime(departure, attendance.timezone)),
        RequestNotice(
            message: 'requests.forgotten_notice'.tr(),
            tone: RequestNoticeTone.warning),
        SizedBox(height: AppSpacing.md),
      ],
      RequestReasonBlock(
          label: 'requests.submitted_reason'.tr(),
          text: item.reason.isEmpty ? 'requests.no_reason'.tr() : item.reason),
    ];
  }

  List<Widget> _progress(EmployeeRequest item, String timezone) {
    final colors = context.colors;
    final hrColor = switch (item.status) {
      'approved' => context.appColors.success,
      'rejected' => colors.error,
      _ => colors.onSurfaceVariant,
    };
    final stageColor = switch (item.managerStage) {
      'approved' => context.appColors.success,
      'rejected' => colors.error,
      'pending' => context.appColors.warning,
      _ => colors.onSurfaceVariant,
    };
    final review = item.managerReview;
    final change = item.lastChange;
    return [
      RequestTimelineStep(
          title: 'requests.step_submitted'.tr(),
          headline: requestTime(item.submittedAt, timezone),
          color: colors.primary,
          icon: Icons.send_rounded),
      RequestTimelineStep(
          title: 'requests.manager_stage'.tr(),
          headline: item.managerStage == null
              ? 'requests.stage_unknown'.tr()
              : 'requests.stages.${item.managerStage!.replaceAll('-', '_')}'
                  .tr(),
          color: stageColor,
          icon: switch (item.managerStage) {
            'approved' => Icons.check_rounded,
            'rejected' => Icons.close_rounded,
            'pending' => Icons.hourglass_top_rounded,
            _ => Icons.remove_rounded,
          },
          lines: [
            if (review != null && item.managerStage == review.status) ...[
              review.by,
              requestTime(review.at, timezone),
              review.reason,
            ],
          ],
          note: 'requests.manager_notice'.tr()),
      RequestTimelineStep(
          title: 'requests.hr_decision'.tr(),
          headline: item.decidedBy ?? 'requests.awaiting_decision'.tr(),
          color: hrColor,
          icon: switch (item.status) {
            'approved' => Icons.check_rounded,
            'rejected' => Icons.close_rounded,
            _ => Icons.hourglass_top_rounded,
          },
          lines: [
            if (item.decidedAt case final at?) requestTime(at, timezone),
            if (item.decisionReason case final reason?) reason,
            if (item.salaryDeductionDays == null)
              'requests.no_deduction'.tr()
            else
              'requests.deduction_days'
                  .tr(namedArgs: {'days': '${item.salaryDeductionDays}'}),
          ],
          isLast: change == null),
      if (change != null)
        RequestTimelineStep(
            title: 'requests.changes.${change.action}'.tr(),
            headline: change.by,
            color: context.appColors.info,
            icon: Icons.history_rounded,
            lines: [requestTime(change.at, timezone), change.reason],
            isLast: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final user = ref.watch(sessionProvider).userOrNull;
    final timezone = user?.timezone ?? 'UTC';
    final item = state.items.where((r) => r.id == widget.id).firstOrNull;
    final gap = SizedBox(height: AppSpacing.md);
    return AppScaffold(
        resizeToAvoidBottomInset: !widget.sheet,
        appBar: widget.sheet ? null : AppTopBar(title: 'requests.details'.tr()),
        body: SafeArea(
            child: Column(children: [
          if (widget.sheet)
            Padding(
                padding: EdgeInsetsDirectional.only(
                    start: AppSpacing.lg,
                    end: AppSpacing.sm,
                    bottom: AppSpacing.sm),
                child: Row(children: [
                  Expanded(
                      child: Text('requests.details'.tr(),
                          style: context.textTheme.titleLarge)),
                  AppIconButton(
                      icon: Icons.close_rounded,
                      size: ButtonSize.large,
                      tooltip: 'requests.close'.tr(),
                      onPressed: () => Navigator.of(context).pop()),
                ])),
          Expanded(
              child: RefreshIndicator(
                  onRefresh: () => ref.read(_provider.notifier).refresh(),
                  child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(AppSpacing.lg.w),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            RequestFeedback(state: state),
                            if (state.data.isLoading &&
                                state.previousItems == null)
                              const Center(child: CircularProgressIndicator()),
                            if (state.data case RequestFailure(:final failure))
                              RequestNotice(
                                  message: failure.message,
                                  tone: RequestNoticeTone.error),
                            if (state.data
                                    is RequestSuccess<List<EmployeeRequest>> &&
                                item == null)
                              RequestNotice(
                                  message: 'requests.unavailable'.tr()),
                            if (item != null) ...[
                              RequestSummaryCard(
                                  type: item.type,
                                  typeLabel: requestTypeLabel(item.type),
                                  status: item.status,
                                  statusLabel: requestStatusLabel(item.status),
                                  submitted:
                                      requestTime(item.submittedAt, timezone),
                                  timezone: timezone,
                                  employeeName:
                                      widget.managed ? item.employeeName : null),
                              gap,
                              RequestPanel(
                                  title: 'requests.information'.tr(),
                                  icon: Icons.description_outlined,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _information(item))),
                              gap,
                              RequestPanel(
                                  title: 'requests.progress'.tr(),
                                  icon: Icons.timeline_rounded,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _progress(item, timezone))),
                              if (item.attachments.isNotEmpty) ...[
                                gap,
                                RequestPanel(
                                    title: 'requests.attachments'.tr(),
                                    icon: Icons.attach_file_rounded,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final attachment
                                              in item.attachments)
                                            Padding(
                                                padding: EdgeInsets.only(
                                                    bottom: AppSpacing.sm),
                                                child: RequestAttachmentButton(
                                                    attachment: attachment)),
                                        ])),
                              ],
                              if (widget.managed &&
                                  !item.canReview(user?.employee?.id)) ...[
                                gap,
                                RequestNotice(
                                    message: 'requests.review_unavailable'.tr(),
                                    tone: RequestNoticeTone.warning),
                              ],
                              if (widget.managed &&
                                  state.data is RequestSuccess<
                                      List<EmployeeRequest>> &&
                                  state.noticeKey !=
                                      'requests.review_unavailable' &&
                                  item.canReview(user?.employee?.id)) ...[
                                gap,
                                RequestPanel(
                                    title: 'requests.recommendation'.tr(),
                                    icon: Icons.fact_check_outlined,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Form(
                                              key: _form,
                                              child: AppTextArea(
                                                  label:
                                                      'requests.review_reason'
                                                          .tr(),
                                                  controller: _reason,
                                                  validator: _validateReason,
                                                  maxLength: 500,
                                                  enabled: !state.busy &&
                                                      state.pending == null)),
                                          for (final status in [
                                            'approved',
                                            'rejected'
                                          ]) ...[
                                            SizedBox(height: AppSpacing.md.h),
                                            AppButton(
                                                label:
                                                    'requests.recommend_$status'
                                                        .tr(),
                                                variant: status == 'approved'
                                                    ? ButtonVariant.primary
                                                    : ButtonVariant.outline,
                                                prefixIcon: ExcludeSemantics(
                                                    child: Icon(status ==
                                                            'approved'
                                                        ? Icons
                                                            .check_circle_outline_rounded
                                                        : Icons
                                                            .cancel_outlined)),
                                                onPressed: state.busy ||
                                                        state.pending != null
                                                    ? null
                                                    : () =>
                                                        _review(item, status)),
                                          ],
                                          if (state.action.isLoading)
                                            const Center(
                                                child:
                                                    CircularProgressIndicator()),
                                        ])),
                              ],
                              if (!widget.managed && item.canWithdraw) ...[
                                gap,
                                RequestPanel(
                                    title: 'requests.withdraw_section'.tr(),
                                    icon: Icons.undo_rounded,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Form(
                                              key: _form,
                                              child: AppTextArea(
                                                  label:
                                                      'requests.withdraw_reason'
                                                          .tr(),
                                                  controller: _reason,
                                                  validator: _validateReason,
                                                  maxLength: 500,
                                                  enabled: !state.busy &&
                                                      state.pending == null)),
                                          SizedBox(height: AppSpacing.md),
                                          AppButton(
                                              label: 'requests.withdraw'.tr(),
                                              variant: ButtonVariant.outline,
                                              isLoading: state.action.isLoading,
                                              onPressed: state.busy ||
                                                      state.pending != null
                                                  ? null
                                                  : () => _withdraw(item)),
                                        ])),
                              ],
                              if (!widget.managed) ...[
                                SizedBox(height: AppSpacing.md),
                                Text('requests.correction_notice'.tr(),
                                    style: context.textTheme.bodySmall
                                        ?.copyWith(
                                            color: context
                                                .colors.onSurfaceVariant)),
                              ],
                            ],
                          ])))),
        ])));
  }
}
