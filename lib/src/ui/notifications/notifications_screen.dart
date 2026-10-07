import 'package:hrmobile/src/imports/imports.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import '../../data/models/employee_notification.dart';
import '../../data/models/employee_request.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_provider.dart';
import '../requests/requests_provider.dart';
import '../requests/request_widgets.dart';
import '../employee_navigation.dart';
import 'notifications_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;
  RequestState<void> _opening = const RequestInitial();
  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationsProvider.notifier).refresh();
    });
  }

  Future<void> _open(EmployeeNotification item) async {
    if (_opening.isLoading) return;
    final identity = _identity();
    setState(() => _opening = const RequestLoading());
    final controller = ref.read(notificationsProvider.notifier);
    final canOpen = await controller.markRead(item.id);
    if (!mounted || _identity() != identity) {
      return;
    }
    if (!canOpen) {
      setState(() => _opening = const RequestInitial());
      return;
    }
    String? route;
    Map<String, String> parameters = const {};
    var unavailable = false;
    var failed = false;
    if (item.requestId case final id?) {
      final managed = item.type == 'manager-review-required';
      final provider = managed ? managedRequestsProvider : requestsProvider;
      await ref.read(provider.notifier).refresh();
      if (!mounted || _identity() != identity) {
        return;
      }
      final requests = ref.read(provider);
      failed = requests.data is! RequestSuccess<List<EmployeeRequest>>;
      unavailable = !requests.items.any((r) => r.id == id);
      route = managed ? 'departmentReviews' : 'requestDetails';
      if (!managed) parameters = {'id': id};
    } else if (item.attendanceId case final id?) {
      await ref.read(attendanceProvider.notifier).refresh();
      if (!mounted || _identity() != identity) {
        return;
      }
      final attendance = ref.read(attendanceProvider);
      failed = attendance.snapshot == null;
      unavailable =
          !(attendance.snapshot?.records.any((r) => r.id == id) ?? false);
      route = 'attendance';
    }
    setState(() => _opening = const RequestInitial());
    if (failed || unavailable) {
      showGlobalToast(
          message: (failed
                  ? 'notifications.target_retry'
                  : 'notifications.target_unavailable')
              .tr());
    } else if (route != null) {
      context.pushNamed(route, pathParameters: parameters);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
        sessionProvider
            .select((s) => (s.userOrNull?.id, s.userOrNull?.employee?.id)),
        (previous, next) {
      setState(() => _opening = const RequestInitial());
    });
    final state = ref.watch(notificationsProvider);
    final user = ref.watch(sessionProvider).userOrNull;
    final items = state.inbox?.items
            .where((item) => !_unreadOnly || item.unread)
            .toList() ??
        <EmployeeNotification>[];
    final busy = state.busy || _opening.isLoading;
    return AppScaffold(
      appBar: AppTopBar(title: 'notifications.title'.tr()),
      body: SafeArea(
          child: ListView(padding: EdgeInsets.all(AppSpacing.lg), children: [
        EmployeeHeading(
            title: 'notifications.title'.tr(),
            subtitle: 'notifications.subtitle'.tr(),
            icon: Icons.notifications_none_rounded),
        if (state.inbox case final inbox?)
          Text(
              'notifications.unread_count'
                  .tr(namedArgs: {'count': '${inbox.unreadCount}'}),
              style: context.textTheme.titleMedium),
        MergeSemantics(
            child: AppSwitch(
                label: 'notifications.unread_only'.tr(),
                value: _unreadOnly,
                onChanged: (value) => setState(() => _unreadOnly = value))),
        if (busy) const Center(child: CircularProgressIndicator()),
        if (state.noticeKey case final key?) Text(key.tr()),
        if (state.data case RequestFailure(:final failure)) ...[
          Text(failure.message, style: TextStyle(color: context.colors.error)),
          if (state.inbox != null) Text('notifications.stale'.tr()),
        ],
        if (state.action case RequestFailure(:final failure)
            when state.noticeKey == null)
          Text(failure.message, style: TextStyle(color: context.colors.error)),
        if (state.data is RequestSuccess<NotificationInbox> && items.isEmpty)
          AppCard(
              child: Text((_unreadOnly
                      ? 'notifications.no_unread'
                      : 'notifications.empty')
                  .tr())),
        for (final item in items) ...[
          AppCard(
              title: item.title,
              leading: Icon(
                  item.unread
                      ? Icons.mark_email_unread_outlined
                      : Icons.drafts_outlined,
                  color: context.colors.primary),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.message),
                    SizedBox(height: AppSpacing.sm),
                    Text(requestTime(item.createdAt, user?.timezone ?? 'UTC'),
                        style: context.textTheme.bodySmall),
                    Text(
                        (item.unread
                                ? 'notifications.unread'
                                : 'notifications.read')
                            .tr(),
                        style: context.textTheme.labelLarge),
                    if (item.requestId != null || item.attendanceId != null)
                      AppTextButton(
                          label: 'notifications.open'.tr(),
                          onPressed: busy ? null : () => _open(item)),
                    if (item.unread)
                      AppTextButton(
                          label: 'notifications.mark_read'.tr(),
                          onPressed: busy
                              ? null
                              : () => ref
                                  .read(notificationsProvider.notifier)
                                  .markRead(item.id)),
                  ])),
          SizedBox(height: AppSpacing.md),
        ],
        AppButton(
            label: 'requests.refresh'.tr(),
            variant: ButtonVariant.outline,
            onPressed: busy
                ? null
                : () => ref.read(notificationsProvider.notifier).refresh()),
      ])),
    );
  }

  (String?, String?) _identity() {
    final user = ref.read(sessionProvider).userOrNull;
    return (user?.id, user?.employee?.id);
  }
}
