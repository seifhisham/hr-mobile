import 'package:hrmobile/src/imports/imports.dart';
import '../employee_navigation.dart';
import 'requests_provider.dart';
import 'request_widgets.dart';
import '../../data/models/employee_request.dart';

class DepartmentReviewsScreen extends ConsumerStatefulWidget {
  const DepartmentReviewsScreen({super.key});
  @override
  ConsumerState<DepartmentReviewsScreen> createState() =>
      _DepartmentReviewsScreenState();
}

class _DepartmentReviewsScreenState
    extends ConsumerState<DepartmentReviewsScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(managedRequestsProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(managedRequestsProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managedRequestsProvider);
    return AppScaffold(
      appBar: AppTopBar(title: 'notifications.department'.tr()),
      body: SafeArea(
          child: ListView(padding: EdgeInsets.all(AppSpacing.lg), children: [
        EmployeeHeading(
            title: 'notifications.department'.tr(),
            subtitle: 'requests.manager_notice'.tr(),
            icon: Icons.groups_outlined),
        if (state.data.isLoading && state.previousItems == null)
          const Center(child: CircularProgressIndicator()),
        if (state.data case RequestFailure(:final failure))
          Text(failure.message),
        if (state.data is RequestSuccess<List<EmployeeRequest>> &&
            state.items.isEmpty)
          Text('notifications.department_empty'.tr()),
        for (final item in state.items) ...[
          AppCard(
              title: item.employeeName,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(requestTypeLabel(item.type)),
                    Text(requestStatusLabel(item.status)),
                    Text(item.managerStage == null
                        ? 'requests.stage_unknown'.tr()
                        : 'requests.stages.${item.managerStage!.replaceAll('-', '_')}'
                            .tr()),
                    AppTextButton(
                        label: 'requests.details'.tr(),
                        onPressed: () => context.pushNamed(
                            'managedRequestDetails',
                            pathParameters: {'id': item.id})),
                  ])),
          SizedBox(height: AppSpacing.md),
        ],
        AppButton(
            label: 'requests.refresh'.tr(),
            variant: ButtonVariant.outline,
            onPressed: state.busy
                ? null
                : () => ref.read(managedRequestsProvider.notifier).refresh()),
      ])),
    );
  }
}
