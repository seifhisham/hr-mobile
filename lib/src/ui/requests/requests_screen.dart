import 'package:hrmobile/src/imports/imports.dart';
import '../employee_navigation.dart';
import '../auth/providers/session_provider.dart';
import '../../data/models/employee_request.dart';
import 'requests_provider.dart';
import 'request_widgets.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});
  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
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
        bottomNavigationBar: const EmployeeNavigation(index: 2),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg.w),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmployeeHeading(
                          title: 'requests.title'.tr(),
                          subtitle: 'design.requests_hint'.tr(),
                          icon: Icons.description_outlined),
                      if (employee == null)
                        Text('account.no_employee'.tr())
                      else ...[
                        AppButton(
                            label: 'requests.new'.tr(),
                            onPressed: state.busy || state.pending != null
                                ? null
                                : () => context.pushNamed('newRequest')),
                        if (managed.items.isNotEmpty)
                          AppTextButton(
                              label: 'notifications.department'.tr(),
                              onPressed: () =>
                                  context.pushNamed('departmentReviews')),
                        SizedBox(height: AppSpacing.lg.h),
                        AppDropdown<String>(
                            label: 'requests.status_filter'.tr(),
                            value: _status ?? '',
                            items: [
                              AppDropdownItem(
                                  value: '',
                                  label: 'requests.all_statuses'.tr()),
                              for (final status in requestStatuses)
                                AppDropdownItem(
                                    value: status,
                                    label: requestStatusLabel(status))
                            ],
                            onChanged: (value) => setState(
                                () => _status = value == '' ? null : value)),
                        SizedBox(height: AppSpacing.md.h),
                        AppDropdown<String>(
                            label: 'requests.type'.tr(),
                            value: _type ?? '',
                            items: [
                              AppDropdownItem(
                                  value: '', label: 'requests.all_types'.tr()),
                              for (final type in requestTypes)
                                AppDropdownItem(
                                    value: type, label: requestTypeLabel(type))
                            ],
                            onChanged: (value) => setState(
                                () => _type = value == '' ? null : value)),
                        AppTextButton(
                            label: 'requests.clear_filters'.tr(),
                            onPressed: () => setState(() {
                                  _status = null;
                                  _type = null;
                                })),
                        RequestFeedback(state: state),
                        if (state.data.isLoading)
                          const Center(child: CircularProgressIndicator()),
                        if (state.data case RequestFailure(:final failure))
                          Text(failure.message,
                              style: TextStyle(color: context.colors.error)),
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
                          AppCard(
                              title: requestTypeLabel(item.type),
                              leading: Icon(Icons.description_outlined,
                                  color: context.colors.primary),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm,
                                            vertical: AppSpacing.xs),
                                        decoration: BoxDecoration(
                                            color: context
                                                .colors.secondaryContainer,
                                            borderRadius: AppBorders.full),
                                        child: Text(
                                            requestStatusLabel(item.status),
                                            style: context.textTheme.labelLarge
                                                ?.copyWith(
                                                    color: context.colors
                                                        .onSecondaryContainer))),
                                    SizedBox(height: AppSpacing.md),
                                    Text(item.from == null
                                        ? 'requests.departure_request'.tr()
                                        : '${item.from} – ${item.to}'),
                                    SizedBox(height: AppSpacing.sm),
                                    Text(item.reason,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    AppTextButton(
                                        label: 'requests.details'.tr(),
                                        onPressed: () => context.pushNamed(
                                            'requestDetails',
                                            pathParameters: {'id': item.id})),
                                  ])),
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
                      ],
                    ]))));
  }
}
