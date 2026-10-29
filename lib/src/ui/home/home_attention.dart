import 'package:hodour/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_provider.dart';
import '../requests/requests_provider.dart';
import '../requests/request_widgets.dart';

final homeAttentionProvider = Provider((ref) {
  final attendance = ref.watch(attendanceProvider);
  final managed = ref.watch(managedRequestsProvider);
  final employeeId =
      ref.watch(sessionProvider.select((s) => s.userOrNull?.employee?.id));
  final snapshot = attendance.snapshot;
  final missing = snapshot?.blockingOlderOpen ??
      (snapshot?.current?.status == 'Missing check-out' &&
              snapshot?.current?.checkOut == null &&
              !snapshot!.hasPendingForgottenCheckout(snapshot.current!)
          ? snapshot.current
          : null);
  final reviews = managed.items.where((item) => item.canReview(employeeId));
  final failed =
      attendance.data is RequestFailure || managed.data is RequestFailure;
  final loaded = attendance.data.isSuccess && managed.data.isSuccess;
  return (
    missing: missing,
    reviews: reviews.toList(),
    failed: failed,
    loaded: loaded
  );
});

class HomeAttention extends ConsumerStatefulWidget {
  const HomeAttention({super.key});
  @override
  ConsumerState<HomeAttention> createState() => _HomeAttentionState();
}

class _HomeAttentionState extends ConsumerState<HomeAttention>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(managedRequestsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final attention = ref.watch(homeAttentionProvider);
    final missing = attention.missing;
    final reviews = attention.reviews;
    final failed = attention.failed;
    final loaded = attention.loaded;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
          header: true,
          child: Text('design.needs_attention'.tr(),
              style: context.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600))),
      SizedBox(height: AppSpacing.md),
      if (failed)
        AppCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text('design.attention_unavailable'.tr()),
              AppTextButton(
                  label: 'design.attention_retry'.tr(),
                  onPressed: () {
                    ref.read(attendanceProvider.notifier).refresh();
                    ref.read(managedRequestsProvider.notifier).refresh();
                  }),
            ]))
      else if (!loaded)
        AppCard(
            child: Row(children: [
          const AppCircularProgress(),
          SizedBox(width: AppSpacing.md),
          Expanded(child: Text('design.attention_loading'.tr())),
        ]))
      else ...[
        if (missing != null) ...[
          _item(
              context,
              Icons.edit_calendar_outlined,
              'requests.types.forgotten_check_out'.tr(),
              missing.workDate,
              () => context.pushNamed('newRequest', queryParameters: {
                    'type': 'forgotten-check-out',
                    'attendanceId': missing.id,
                  })),
          SizedBox(height: AppSpacing.sm),
        ],
        for (final item in reviews) ...[
          _item(
              context,
              Icons.fact_check_outlined,
              'design.review_request'.tr(),
              '${item.employeeName} · ${requestTypeLabel(item.type)}',
              () => context.pushNamed('managedRequestDetails',
                  pathParameters: {'id': item.id})),
          SizedBox(height: AppSpacing.sm),
        ],
        if (missing == null && reviews.isEmpty)
          AppCard(
              child: Row(children: [
            Icon(Icons.check_circle_outline_rounded,
                color: context.colors.primary),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Text('design.attention_clear'.tr(),
                    style: context.textTheme.bodyMedium)),
          ])),
      ],
    ]);
  }

  Widget _item(BuildContext context, IconData icon, String title,
          String subtitle, VoidCallback onTap) =>
      AppCard(
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: context.colors.primary),
          SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.textTheme.titleSmall),
              SizedBox(height: AppSpacing.xs),
              Text(subtitle,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          )),
          SizedBox(width: AppSpacing.sm),
          Icon(Directionality.of(context) == TextDirection.rtl
              ? Icons.chevron_left_rounded
              : Icons.chevron_right_rounded),
        ]),
      );
}
