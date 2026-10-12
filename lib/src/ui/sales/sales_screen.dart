import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../auth/providers/session_provider.dart';
import '../employee_navigation.dart';
import 'sales_provider.dart';
import 'sales_widgets.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key, this.team = false});
  final bool team;
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  bool get team => widget.team;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(salesListProvider(team).notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).userOrNull;
    final accessState = ref.watch(salesAccessProvider);
    final access = accessValue(accessState);
    final state = ref.watch(salesListProvider(team));
    final controller = ref.read(salesListProvider(team).notifier);
    final dashboard = state.dashboard;
    final allowed =
        user != null && (team ? access.canReview : user.employee != null);
    final rows = dashboard?.performance
            .where((r) =>
                state.employeeId == null || r.employeeId == state.employeeId)
            .toList() ??
        [];
    final employeeChoices = <String, String>{
      for (final row in dashboard?.performance ?? <SalesPerformance>[])
        row.employeeId: '${row.employeeName} · ${row.employeeNumber}',
      for (final item in dashboard?.activities ?? <SalesActivity>[])
        item.employeeId: '${item.employeeName} · ${item.employeeNumber}',
    };
    return AppScaffold(
        appBar: team
            ? AppTopBar(
                title: 'sales.team_title'.tr(),
                titleWidget: Text('sales.team_title'.tr(),
                    style: context.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)))
            : null,
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: () async {
                  await ref.read(salesAccessProvider.notifier).refresh();
                  await controller.refresh();
                },
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!team)
                            EmployeeHeading(
                                title: 'sales.title'.tr(),
                                subtitle: 'sales.subtitle'.tr(),
                                icon: Icons.home_work_outlined),
                          SalesNotice(
                              text: (team
                                      ? 'sales.team_hint'
                                      : 'sales.counting_hint')
                                  .tr()),
                          SizedBox(height: AppSpacing.md),
                          if (accessState.isLoading)
                            const Center(child: CircularProgressIndicator()),
                          if (accessState
                              case RequestFailure(:final failure)) ...[
                            Text(failure.message,
                                style: TextStyle(color: context.colors.error)),
                            AppButton(
                                label: 'sales.refresh_access'.tr(),
                                variant: ButtonVariant.outline,
                                onPressed: () => ref
                                    .read(salesAccessProvider.notifier)
                                    .refresh()),
                          ],
                          if (!allowed)
                            Text((team
                                    ? 'sales.review_unavailable'
                                    : 'account.no_employee')
                                .tr()),
                          if (allowed) ...[
                            if (!team && access.canSubmit) ...[
                              AppButton(
                                  label: 'sales.register'.tr(),
                                  onPressed: () =>
                                      context.pushNamed('newSalesActivity')),
                              SizedBox(height: AppSpacing.sm),
                            ],
                            if (!team &&
                                !access.canSubmit &&
                                accessState is RequestSuccess<SalesAccess>)
                              Padding(
                                  padding:
                                      EdgeInsets.only(bottom: AppSpacing.md),
                                  child: Text('sales.read_only'.tr())),
                            if (!team && access.canReview)
                              AppButton(
                                  label: 'sales.team_title'.tr(),
                                  variant: ButtonVariant.outline,
                                  onPressed: () =>
                                      context.pushNamed('teamSales')),
                            SizedBox(height: AppSpacing.lg),
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  Text('sales.reporting_month'.tr(),
                                      style: context.textTheme.labelLarge),
                                  Row(children: [
                                    IconButton(
                                        tooltip: 'sales.previous_month'.tr(),
                                        icon: const Icon(Icons.arrow_back),
                                        onPressed: () =>
                                            _moveMonth(controller, state, -1)),
                                    Expanded(
                                        child: AppTextButton(
                                            label: DateFormat.yMMMM(
                                                    context.locale.toString())
                                                .format(DateTime.parse(
                                                    '${state.month}-01')),
                                            onPressed: () => _chooseMonth(
                                                context, controller, state))),
                                    IconButton(
                                        tooltip: 'sales.next_month'.tr(),
                                        icon: const Icon(Icons.arrow_forward),
                                        onPressed: () =>
                                            _moveMonth(controller, state, 1)),
                                  ]),
                                ])),
                            SizedBox(height: AppSpacing.lg),
                            if (team && employeeChoices.isNotEmpty) ...[
                              AppDropdown<String>(
                                  label: 'sales.employee_filter'.tr(),
                                  value: state.employeeId ?? '',
                                  items: [
                                    AppDropdownItem(
                                        value: '',
                                        label: 'sales.all_employees'.tr()),
                                    for (final entry in employeeChoices.entries)
                                      AppDropdownItem(
                                          value: entry.key, label: entry.value),
                                  ],
                                  onChanged: (value) => controller.filter(
                                      kind: state.kind,
                                      status: state.status,
                                      employeeId: value == '' ? null : value)),
                              SizedBox(height: AppSpacing.md),
                            ],
                            if (state.data.isLoading && dashboard == null)
                              const Center(child: CircularProgressIndicator()),
                            if (state.data case RequestFailure(:final failure))
                              Text(failure.message,
                                  style:
                                      TextStyle(color: context.colors.error)),
                            for (final row in rows) ...[
                              SalesPerformanceCard(row: row, team: team),
                              SizedBox(height: AppSpacing.md)
                            ],
                            if (dashboard != null && rows.isEmpty)
                              AppCard(child: Text('sales.no_summary'.tr())),
                            SizedBox(height: AppSpacing.lg),
                            Text('sales.activity_history'.tr(),
                                style: context.textTheme.titleLarge),
                            SizedBox(height: AppSpacing.md),
                            AppDropdown<String>(
                                label: 'sales.type'.tr(),
                                value: state.kind ?? '',
                                items: [
                                  AppDropdownItem(
                                      value: '', label: 'sales.all_types'.tr()),
                                  for (final kind in salesKinds)
                                    AppDropdownItem(
                                        value: kind,
                                        label: salesKindLabel(kind)),
                                ],
                                onChanged: (v) => controller.filter(
                                    kind: v == '' ? null : v,
                                    status: state.status,
                                    employeeId: state.employeeId)),
                            SizedBox(height: AppSpacing.md),
                            AppDropdown<String>(
                                label: 'sales.status'.tr(),
                                value: state.status ?? '',
                                items: [
                                  AppDropdownItem(
                                      value: '',
                                      label: 'sales.all_statuses'.tr()),
                                  for (final status in salesStatuses)
                                    AppDropdownItem(
                                        value: status,
                                        label: salesStatusLabel(status)),
                                ],
                                onChanged: (v) => controller.filter(
                                    kind: state.kind,
                                    status: v == '' ? null : v,
                                    employeeId: state.employeeId)),
                            if (dashboard != null &&
                                dashboard.activities.isEmpty)
                              AppEmptyState(
                                  icon: Icons.home_work_outlined,
                                  title: 'sales.empty'.tr(),
                                  subtitle: 'sales.empty_hint'.tr()),
                            for (final item in dashboard?.activities ??
                                <SalesActivity>[]) ...[
                              SizedBox(height: AppSpacing.md),
                              SalesActivityCard(
                                  item: item,
                                  team: team,
                                  onTap: () => context.pushNamed(
                                          'salesActivityDetails',
                                          pathParameters: {
                                            'id': item.id
                                          },
                                          queryParameters: {
                                            if (team) 'team': 'true'
                                          })),
                            ],
                          ],
                        ])))));
  }

  void _moveMonth(
      SalesListController controller, SalesListState state, int delta) {
    final date = DateTime.parse('${state.month}-01');
    final next = DateTime(date.year, date.month + delta);
    if (next.year < 1900 || next.year > 2100) return;
    controller.filter(
        month: DateFormat('yyyy-MM').format(next),
        kind: state.kind,
        status: state.status);
  }

  Future<void> _chooseMonth(BuildContext context,
      SalesListController controller, SalesListState state) async {
    final initial = DateTime.parse('${state.month}-01');
    var year = initial.year, month = initial.month;
    final date = await showDialog<DateTime>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, update) => AlertDialog(
                  title: Text('sales.reporting_month'.tr()),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppDropdown<int>(
                        label: 'sales.year'.tr(),
                        value: year,
                        items: [
                          for (var value = 1900; value <= 2100; value++)
                            AppDropdownItem(value: value, label: '$value')
                        ],
                        onChanged: (value) {
                          if (value != null) update(() => year = value);
                        }),
                    SizedBox(height: AppSpacing.md),
                    AppDropdown<int>(
                        label: 'sales.month'.tr(),
                        value: month,
                        items: [
                          for (var value = 1; value <= 12; value++)
                            AppDropdownItem(
                                value: value,
                                label:
                                    DateFormat.MMMM(context.locale.toString())
                                        .format(DateTime(year, value)))
                        ],
                        onChanged: (value) {
                          if (value != null) update(() => month = value);
                        }),
                  ])),
                  actions: [
                    AppTextButton(
                        label: 'sales.cancel'.tr(),
                        onPressed: () => Navigator.of(dialogContext).pop()),
                    AppTextButton(
                        label: 'sales.confirm'.tr(),
                        onPressed: () => Navigator.of(dialogContext)
                            .pop(DateTime(year, month))),
                  ],
                )));
    if (date != null) {
      await controller.filter(
          month: DateFormat('yyyy-MM').format(date),
          kind: state.kind,
          status: state.status);
    }
  }
}
