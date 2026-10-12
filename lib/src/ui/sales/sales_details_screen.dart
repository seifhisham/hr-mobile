import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../auth/providers/session_provider.dart';
import 'sales_provider.dart';
import 'sales_widgets.dart';

class SalesDetailsScreen extends ConsumerStatefulWidget {
  const SalesDetailsScreen({super.key, required this.id, this.team = false});
  final String id;
  final bool team;
  @override
  ConsumerState<SalesDetailsScreen> createState() => _SalesDetailsScreenState();
}

class _SalesDetailsScreenState extends ConsumerState<SalesDetailsScreen> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(sessionProvider).userOrNull?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(salesMutationProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _review(SalesActivity item, String status) async {
    if (!_form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text((status == 'verified'
                        ? 'sales.verify'
                        : 'sales.return_activity')
                    .tr()),
                content: Text((status == 'verified'
                        ? 'sales.verify_confirmation'
                        : 'sales.return_confirmation')
                    .tr()),
                actions: [
                  AppTextButton(
                      label: 'sales.cancel'.tr(),
                      onPressed: () => Navigator.of(context).pop(false)),
                  AppTextButton(
                      label: 'sales.confirm'.tr(),
                      onPressed: () => Navigator.of(context).pop(true)),
                ]));
    if (confirmed != true ||
        !mounted ||
        ref.read(sessionProvider).userOrNull?.id != _owner) {
      return;
    }
    await ref
        .read(salesMutationProvider.notifier)
        .review(item, status, _reason.text);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).userOrNull;
    final access = accessValue(ref.watch(salesAccessProvider));
    final detail = ref.watch(salesDetailProvider(widget.id));
    final mutation = ref.watch(salesMutationProvider);
    final item =
        detail.value?.fold<SalesActivity?>((_) => null, (item) => item);
    ref.listen(sessionProvider.select((s) => s.userOrNull?.id), (_, next) {
      if (next != _owner) _reason.clear();
    });
    if (user == null || user.id != _owner) return const SizedBox.shrink();
    final owner = user.employee?.id;
    final busy = mutation.action.isLoading || mutation.pending != null;
    return AppScaffold(
        appBar: AppTopBar(
            title: 'sales.details'.tr(),
            titleWidget: Text('sales.details'.tr(),
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600))),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (detail.isLoading)
                        const Center(child: CircularProgressIndicator()),
                      if (detail.value?.fold<Failure?>((f) => f, (_) => null)
                          case final failure?)
                        Text(failure.message,
                            style: TextStyle(color: context.colors.error)),
                      if (item != null) ...[
                        SalesDetailFields(
                            item: item,
                            timezone: user.timezone,
                            team: widget.team),
                        SizedBox(height: AppSpacing.lg),
                        const SalesMutationFeedback(),
                        if (access.canSubmit && item.canCorrect(owner))
                          AppButton(
                              label: 'sales.correct'.tr(),
                              onPressed: busy
                                  ? null
                                  : () => context.pushNamed('editSalesActivity',
                                      pathParameters: {'id': item.id})),
                        if (item.employeeId == owner &&
                            item.status == 'verified')
                          Text('sales.verified_read_only'.tr()),
                        if (access.canReview &&
                            (item.canVerify(owner) ||
                                item.canReturn(owner))) ...[
                          SalesNotice(text: 'sales.review_hint'.tr()),
                          SizedBox(height: AppSpacing.md),
                          Form(
                              key: _form,
                              child: AppTextField(
                                  label: 'sales.review_reason_hint'.tr(),
                                  controller: _reason,
                                  enabled: !busy,
                                  maxLines: 3,
                                  validator: (value) =>
                                      (value?.trim().length ?? 0) < 5 ||
                                              (value?.trim().length ?? 0) > 500
                                          ? 'sales.errors.reason'.tr()
                                          : null)),
                          SizedBox(height: AppSpacing.md),
                          if (item.canVerify(owner))
                            AppButton(
                                label: 'sales.verify'.tr(),
                                onPressed: busy
                                    ? null
                                    : () => _review(item, 'verified')),
                          SizedBox(height: AppSpacing.sm),
                          if (item.canReturn(owner))
                            AppButton(
                                label: 'sales.return_activity'.tr(),
                                variant: ButtonVariant.outline,
                                onPressed: busy
                                    ? null
                                    : () => _review(item, 'returned')),
                        ],
                      ],
                      AppTextButton(
                          label: 'sales.refresh'.tr(),
                          onPressed: () {
                            ref.invalidate(salesDetailProvider(widget.id));
                            ref.read(salesAccessProvider.notifier).refresh();
                          }),
                    ]))));
  }
}
