import 'package:hodour/src/imports/imports.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import '../../data/models/employee_notification.dart';
import '../../data/models/employee_request.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_provider.dart';
import '../requests/requests_provider.dart';
import '../requests/request_details_screen.dart';
import '../employee_navigation.dart';
import 'notification_card.dart';
import 'notification_view.dart';
import 'notifications_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationStatusFilter _status = NotificationStatusFilter.all;
  NotificationCategory? _category;
  bool _needsAction = false;
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
      if (managed && !failed && !unavailable) {
        ref.read(provider.notifier).clearAction();
        setState(() => _opening = const RequestInitial());
        await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(borderRadius: AppBorders.xl),
            clipBehavior: Clip.antiAlias,
            builder: (context) => FractionallySizedBox(
                heightFactor: 0.9,
                child: Padding(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom),
                    child: RequestDetailsScreen(
                        id: id, managed: true, sheet: true))));
        return;
      }
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
        sessionProvider.select(
            (s) => (s.userOrNull?.sessionIdentity, s.userOrNull?.employee?.id)),
        (previous, next) {
      setState(() => _opening = const RequestInitial());
    });
    final state = ref.watch(notificationsProvider);
    final user = ref.watch(sessionProvider).userOrNull;
    final all = state.inbox?.items ?? <EmployeeNotification>[];
    // Category chips count what the status filter leaves, so the numbers
    // always match what tapping a chip will show.
    final byStatus =
        filterNotifications(all, status: _status, needsAction: _needsAction);
    final counts = categoryCounts(byStatus);
    final items = filterNotifications(all,
        status: _status, category: _category, needsAction: _needsAction);
    // Shown only to people who actually receive approval requests.
    final actionCount =
        filterNotifications(all, status: _status, needsAction: true).length;
    final timezone = user?.timezone ?? 'UTC';
    final now = DateTime.now();
    final filtered = _status != NotificationStatusFilter.all ||
        _category != null ||
        _needsAction;
    final busy = state.busy || _opening.isLoading;
    return AppScaffold(
      appBar: AppTopBar(title: 'notifications.title'.tr()),
      body: SafeArea(
          child: RefreshIndicator(
              onRefresh: () async {
                if (!busy) {
                  await ref.read(notificationsProvider.notifier).refresh();
                }
              },
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(AppSpacing.lg),
                  children: [
                    EmployeeHeading(
                        title: 'notifications.title'.tr(),
                        subtitle: 'notifications.subtitle'.tr(),
                        icon: Icons.notifications_none_rounded),
                    if (state.inbox case final inbox?) ...[
                      AppSegmentedControl<NotificationStatusFilter>(
                          segments: [
                            AppSegment(
                                value: NotificationStatusFilter.all,
                                label: 'notifications.filter_all'.tr()),
                            AppSegment(
                                value: NotificationStatusFilter.unread,
                                label: 'notifications.filter_unread'.tr(
                                    namedArgs: {
                                      'count': '${inbox.unreadCount}'
                                    })),
                          ],
                          value: _status,
                          onChanged: (value) =>
                              setState(() => _status = value)),
                      if (counts.length > 1 ||
                          _category != null ||
                          actionCount > 0 ||
                          _needsAction) ...[
                        SizedBox(height: AppSpacing.md),
                        Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              if (actionCount > 0 || _needsAction)
                                AppChip(
                                    label:
                                        '${'notifications.action_needed'.tr()} ($actionCount)',
                                    avatar: const Icon(
                                        Icons.pending_actions_rounded,
                                        size: 18),
                                    selected: _needsAction,
                                    onSelected: (value) =>
                                        setState(() => _needsAction = value)),
                              AppChip(
                                  label:
                                      '${'notifications.filter_all'.tr()} (${byStatus.length})',
                                  selected: _category == null,
                                  onSelected: (_) =>
                                      setState(() => _category = null)),
                              for (final category in NotificationCategory.values)
                                if ((counts[category] ?? 0) > 0 ||
                                    _category == category)
                                  AppChip(
                                      label:
                                          '${notificationCategoryKey(category).tr()} (${counts[category] ?? 0})',
                                      avatar: Icon(
                                          notificationCategoryIcon(category),
                                          size: 18),
                                      selected: _category == category,
                                      onSelected: (_) => setState(() =>
                                          _category = _category == category
                                              ? null
                                              : category)),
                            ]),
                      ],
                      SizedBox(height: AppSpacing.lg),
                    ],
                    if (busy) const Center(child: CircularProgressIndicator()),
                    if (state.noticeKey case final key?) Text(key.tr()),
                    if (state.data case RequestFailure(:final failure)) ...[
                      Text(failure.message,
                          style: TextStyle(color: context.colors.error)),
                      if (state.inbox != null) Text('notifications.stale'.tr()),
                    ],
                    if (state.action case RequestFailure(:final failure)
                        when state.noticeKey == null)
                      Text(failure.message,
                          style: TextStyle(color: context.colors.error)),
                    if (state.data is RequestSuccess<NotificationInbox> &&
                        items.isEmpty)
                      AppCard(
                          child: Column(children: [
                        AppEmptyState(
                            icon: filtered
                                ? Icons.filter_alt_off_outlined
                                : Icons.notifications_none_rounded,
                            title: (filtered
                                    ? (_needsAction &&
                                            _category == null &&
                                            _status ==
                                                NotificationStatusFilter.all
                                        ? 'notifications.no_action'
                                        : _status ==
                                                    NotificationStatusFilter
                                                        .unread &&
                                                _category == null &&
                                                !_needsAction
                                            ? 'notifications.no_unread'
                                            : 'notifications.no_results')
                                    : 'notifications.empty')
                                .tr()),
                        if (filtered) ...[
                          SizedBox(height: AppSpacing.md),
                          AppButton(
                              label: 'notifications.clear_filters'.tr(),
                              variant: ButtonVariant.outline,
                              onPressed: () => setState(() {
                                    _status = NotificationStatusFilter.all;
                                    _category = null;
                                    _needsAction = false;
                                  })),
                        ],
                      ])),
                    for (final (day, group)
                        in groupNotificationsByDay(items, now, timezone)) ...[
                      Padding(
                          padding: EdgeInsets.only(
                              top: AppSpacing.sm, bottom: AppSpacing.sm),
                          child: Semantics(
                              header: true,
                              child: Text(
                                  switch (day) {
                                    NotificationDay.today =>
                                      'notifications.group_today',
                                    NotificationDay.yesterday =>
                                      'notifications.group_yesterday',
                                    NotificationDay.earlier =>
                                      'notifications.group_earlier',
                                  }
                                      .tr(),
                                  style: context.textTheme.titleSmall
                                      ?.copyWith(
                                          color: context
                                              .colors.onSurfaceVariant)))),
                      for (final item in group) ...[
                        NotificationCard(
                            item: item,
                            time: notificationTime(
                                item.createdAt, now, timezone),
                            busy: busy,
                            onOpen: () => _open(item),
                            onMarkRead: () => ref
                                .read(notificationsProvider.notifier)
                                .markRead(item.id)),
                        SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ]))),
    );
  }

  (Object?, String?) _identity() {
    final user = ref.read(sessionProvider).userOrNull;
    return (user?.sessionIdentity, user?.employee?.id);
  }
}
