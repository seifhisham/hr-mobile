import 'package:hodour/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../../data/models/employee_request.dart';
import 'requests_provider.dart';
import 'request_widgets.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});
  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item});
  final EmployeeRequest item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appColors = context.appColors;
    final (statusColor, statusIcon) = switch (item.status) {
      'approved' => (appColors.success, Icons.check_circle_outline_rounded),
      'rejected' => (colors.error, Icons.cancel_outlined),
      'pending' => (appColors.warning, Icons.schedule_rounded),
      _ => (colors.onSurfaceVariant, Icons.remove_circle_outline_rounded),
    };
    final icon = switch (item.type) {
      'sick' => Icons.health_and_safety_outlined,
      'mission' => Icons.work_outline_rounded,
      'excuse' || 'forgotten-check-out' => Icons.more_time_rounded,
      'urgent' => Icons.priority_high_rounded,
      _ => Icons.event_available_rounded,
    };
    void open() =>
        context.pushNamed('requestDetails', pathParameters: {'id': item.id});
    return AppCard(
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: EdgeInsets.all(AppSpacing.ms),
                decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: AppBorders.lg),
                child: Icon(icon, color: colors.onPrimaryContainer)),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Text(requestTypeLabel(item.type),
                    style: context.textTheme.titleMedium)),
          ]),
          SizedBox(height: AppSpacing.md),
          Container(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: AppBorders.full),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, color: statusColor, size: AppSpacing.md),
                SizedBox(width: AppSpacing.xs),
                Flexible(
                    child: Text(requestStatusLabel(item.status),
                        style: context.textTheme.labelLarge
                            ?.copyWith(color: colors.onSurface))),
              ])),
          SizedBox(height: AppSpacing.md),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.date_range_outlined,
                color: colors.onSurfaceVariant, size: AppSpacing.ml),
            SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(
                    item.from == null
                        ? 'requests.departure_request'.tr()
                        : '${item.from} – ${item.to}',
                    style: context.textTheme.bodyMedium)),
          ]),
          if (item.reason.isNotEmpty) ...[
            SizedBox(height: AppSpacing.sm),
            Text(item.reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ],
          SizedBox(height: AppSpacing.sm),
          AppTextButton(label: 'requests.details'.tr(), onPressed: open),
        ]));
  }
}

class _RequestsScreenState extends ConsumerState<RequestsScreen>
    with WidgetsBindingObserver {
  String? _status, _type;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(requestsProvider.notifier).refresh();
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
      ref.read(requestsProvider.notifier).refresh();
    }
  }

  List<EmployeeRequest> _filtered(RequestsState state) =>
      filterRequests(state.items, status: _status, type: _type);
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(requestsProvider);
    final managed = ref.watch(managedRequestsProvider);
    final employee =
        ref.watch(sessionProvider.select((s) => s.userOrNull?.employee));
    return AppScaffold(
        body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
                onRefresh: () => ref.read(requestsProvider.notifier).refresh(),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.description_rounded,
                                        color: context.appColors.onHomeBlue,
                                        size: AppSpacing.xl),
                                    SizedBox(height: AppSpacing.md),
                                    Semantics(
                                        header: true,
                                        child: Text('requests.title'.tr(),
                                            style: context
                                                .textTheme.headlineMedium
                                                ?.copyWith(
                                                    color: context.appColors
                                                        .onHomeBlue))),
                                    SizedBox(height: AppSpacing.xs),
                                    Text('design.requests_hint'.tr(),
                                        style: context.textTheme.bodyMedium
                                            ?.copyWith(
                                                color: context
                                                    .appColors.onHomeBlue)),
                                    if (employee != null) ...[
                                      SizedBox(height: AppSpacing.lg),
                                      AppButton(
                                          label: 'requests.new'.tr(),
                                          color: context
                                              .colors.surfaceContainerLow,
                                          textColor: context.colors.primary,
                                          prefixIcon: Icon(Icons.add_rounded,
                                              color: context.colors.primary),
                                          onPressed: state.busy ||
                                                  state.pending != null
                                              ? null
                                              : () => context
                                                  .pushNamed('newRequest')),
                                    ],
                                  ])),
                          SizedBox(height: AppSpacing.lg),
                          if (employee == null)
                            Text('account.no_employee'.tr())
                          else ...[
                            Semantics(
                                header: true,
                                child: Text('requests.type'.tr(),
                                    style: context.textTheme.titleLarge)),
                            SizedBox(height: AppSpacing.md),
                            RequestTypeCards(
                                onSelected: state.busy || state.pending != null
                                    ? null
                                    : (type) => context.pushNamed('newRequest',
                                        queryParameters: {'type': type})),
                            SizedBox(height: AppSpacing.lg),
                            if (managed.items.isNotEmpty)
                              AppTextButton(
                                  label: 'notifications.department'.tr(),
                                  onPressed: () =>
                                      context.pushNamed('departmentReviews')),
                            SizedBox(height: AppSpacing.lg.h),
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  AppDropdown<String>(
                                      label: 'requests.status_filter'.tr(),
                                      value: _status ?? '',
                                      items: [
                                        AppDropdownItem(
                                            value: '',
                                            label:
                                                'requests.all_statuses'.tr()),
                                        for (final status in requestStatuses)
                                          AppDropdownItem(
                                              value: status,
                                              label: requestStatusLabel(status))
                                      ],
                                      onChanged: (value) => setState(() =>
                                          _status =
                                              value == '' ? null : value)),
                                  SizedBox(height: AppSpacing.md.h),
                                  AppDropdown<String>(
                                      label: 'requests.type'.tr(),
                                      value: _type ?? '',
                                      items: [
                                        AppDropdownItem(
                                            value: '',
                                            label: 'requests.all_types'.tr()),
                                        for (final type in requestTypes)
                                          AppDropdownItem(
                                              value: type,
                                              label: requestTypeLabel(type))
                                      ],
                                      onChanged: (value) => setState(() =>
                                          _type = value == '' ? null : value)),
                                  AppTextButton(
                                      label: 'requests.clear_filters'.tr(),
                                      onPressed: () => setState(() {
                                            _status = null;
                                            _type = null;
                                          })),
                                ])),
                            SizedBox(height: AppSpacing.md),
                            RequestFeedback(state: state),
                            if (state.data.isLoading &&
                                state.previousItems == null)
                              const Center(child: CircularProgressIndicator()),
                            if (state.data case RequestFailure(:final failure))
                              Text(failure.message,
                                  style:
                                      TextStyle(color: context.colors.error)),
                            if (state.data
                                    is RequestSuccess<List<EmployeeRequest>> &&
                                _filtered(state).isEmpty)
                              AppCard(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Icon(Icons.inbox_outlined,
                                        color: context.colors.primary),
                                    SizedBox(height: AppSpacing.md),
                                    Text(
                                        (state.items.isEmpty
                                                ? 'requests.empty'
                                                : 'requests.no_matches')
                                            .tr(),
                                        textAlign: TextAlign.center),
                                  ])),
                            for (final item in _filtered(state)) ...[
                              SizedBox(height: AppSpacing.md.h),
                              _RequestCard(item: item),
                            ],
                            SizedBox(height: AppSpacing.lg.h),
                          ],
                        ])))));
  }
}
