import 'package:hrmobile/src/imports/imports.dart';
import '../employee_navigation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import '../auth/providers/session_provider.dart';
import '../../data/models/employee_request.dart';
import 'requests_provider.dart';
import 'request_widgets.dart';

class RequestDetailsScreen extends ConsumerStatefulWidget {
  const RequestDetailsScreen(
      {super.key, required this.id, this.managed = false});
  final String id;
  final bool managed;
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

  String? _validateReason(String? value) =>
      (value?.trim().length ?? 0) < 5 || (value?.trim().length ?? 0) > 500
          ? 'requests.reason_invalid'.tr()
          : null;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final user = ref.watch(sessionProvider).userOrNull;
    final timezone = user?.timezone ?? 'UTC';
    final item = state.items.where((r) => r.id == widget.id).firstOrNull;
    return AppScaffold(
        appBar: AppTopBar(title: 'requests.details'.tr()),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg.w),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmployeeHeading(
                          title: 'requests.details'.tr(),
                          subtitle: 'design.requests_hint'.tr(),
                          icon: Icons.description_outlined),
                      RequestFeedback(state: state),
                      if (state.data.isLoading)
                        const Center(child: CircularProgressIndicator()),
                      if (state.data case RequestFailure(:final failure))
                        Text(failure.message),
                      if (state.data is RequestSuccess<List<EmployeeRequest>> &&
                          item == null)
                        Text('requests.unavailable'.tr()),
                      if (item != null) ...[
                        if (widget.managed)
                          Text(item.employeeName,
                              style: context.textTheme.titleLarge),
                        Text(requestTypeLabel(item.type),
                            style: context.textTheme.headlineSmall),
                        Text(requestStatusLabel(item.status),
                            style: context.textTheme.titleLarge),
                        SizedBox(height: AppSpacing.md.h),
                        AppCard(
                            title: 'requests.submitted'.tr(),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(requestTime(item.submittedAt, timezone)),
                                  Text(timezone),
                                  if (item.from != null)
                                    Text('${item.from} – ${item.to}'),
                                  if (item.durationMinutes != null)
                                    Text('requests.minutes_per_day'.tr(
                                        namedArgs: {
                                          'minutes': '${item.durationMinutes}'
                                        })),
                                  if (item.excuseType != null)
                                    Text(
                                        'requests.excuse_types.${item.excuseType!.replaceAll('-', '_')}'
                                            .tr()),
                                  if (item.shiftId != null)
                                    Text('requests.assigned_shift'.tr()),
                                  if (item.attendance
                                      case final attendance?) ...[
                                    Text('requests.record_workday'.tr(
                                        namedArgs: {
                                          'date': attendance.workDate
                                        })),
                                    Text(
                                        '${'attendance.check_in'.tr()}: ${requestTime(attendance.checkIn, attendance.timezone)}'),
                                    if (item.proposedCheckOut
                                        case final departure?)
                                      Text(
                                          '${'requests.proposed_departure'.tr()}: ${requestTime(departure, attendance.timezone)}'),
                                    Text(attendance.timezone),
                                    Text('requests.forgotten_notice'.tr()),
                                  ],
                                  Text(item.reason.isEmpty
                                      ? 'requests.no_reason'.tr()
                                      : item.reason),
                                ])),
                        SizedBox(height: AppSpacing.md.h),
                        AppCard(
                            title: 'requests.manager_stage'.tr(),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.managerStage == null
                                      ? 'requests.stage_unknown'.tr()
                                      : 'requests.stages.${item.managerStage!.replaceAll('-', '_')}'
                                          .tr()),
                                  if (item.managerReview case final review?
                                      when item.managerStage ==
                                          review.status) ...[
                                    Text(review.by),
                                    Text(requestTime(review.at, timezone)),
                                    Text(review.reason),
                                  ],
                                  Text('requests.manager_notice'.tr()),
                                ])),
                        SizedBox(height: AppSpacing.md.h),
                        AppCard(
                            title: 'requests.hr_decision'.tr(),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.decidedBy ??
                                      'requests.awaiting_decision'.tr()),
                                  if (item.decidedAt case final at?)
                                    Text(requestTime(at, timezone)),
                                  if (item.decisionReason case final reason?)
                                    Text(reason),
                                  Text(item.salaryDeductionDays == null
                                      ? 'requests.no_deduction'.tr()
                                      : 'requests.deduction_days'
                                          .tr(namedArgs: {
                                          'days': '${item.salaryDeductionDays}'
                                        })),
                                ])),
                        if (item.lastChange case final change?) ...[
                          SizedBox(height: AppSpacing.md.h),
                          AppCard(
                              title: 'requests.changes.${change.action}'.tr(),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(change.by),
                                    Text(requestTime(change.at, timezone)),
                                    Text(change.reason)
                                  ])),
                        ],
                        for (final attachment in item.attachments) ...[
                          SizedBox(height: AppSpacing.md.h),
                          RequestAttachmentButton(attachment: attachment),
                        ],
                        if (!widget.managed && item.canWithdraw) ...[
                          SizedBox(height: AppSpacing.lg.h),
                          Form(
                              key: _form,
                              child: AppTextArea(
                                  label: 'requests.withdraw_reason'.tr(),
                                  controller: _reason,
                                  validator: _validateReason,
                                  maxLength: 500,
                                  enabled:
                                      !state.busy && state.pending == null)),
                          AppButton(
                              label: 'requests.withdraw'.tr(),
                              variant: ButtonVariant.outline,
                              isLoading: state.action.isLoading,
                              onPressed: state.busy || state.pending != null
                                  ? null
                                  : () => _withdraw(item)),
                        ],
                        if (!widget.managed)
                          Text('requests.correction_notice'.tr()),
                      ],
                      SizedBox(height: AppSpacing.lg.h),
                      AppButton(
                          label: (state.pending == null
                                  ? 'requests.refresh'
                                  : 'requests.reconcile')
                              .tr(),
                          variant: ButtonVariant.outline,
                          isLoading: state.data.isLoading,
                          onPressed: state.busy
                              ? null
                              : () => ref
                                  .read(requestsProvider.notifier)
                                  .refresh()),
                    ]))));
  }
}
