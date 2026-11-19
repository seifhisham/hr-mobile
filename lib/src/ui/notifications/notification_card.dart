import 'package:hodour/src/imports/imports.dart';
import '../../data/models/employee_notification.dart';
import 'notification_view.dart';

String notificationCategoryKey(NotificationCategory category) =>
    switch (category) {
      NotificationCategory.requests => 'notifications.category_requests',
      NotificationCategory.attendance => 'notifications.category_attendance',
      NotificationCategory.other => 'notifications.category_other',
    };

IconData notificationCategoryIcon(NotificationCategory category) =>
    switch (category) {
      NotificationCategory.requests => Icons.assignment_outlined,
      NotificationCategory.attendance => Icons.fingerprint_rounded,
      NotificationCategory.other => Icons.notifications_none_rounded,
    };

/// One inbox entry: category icon, title, message, time, and a single
/// obvious action. Unread entries are tinted and carry a dot.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.item,
    required this.time,
    required this.busy,
    required this.onOpen,
    required this.onMarkRead,
  });

  final EmployeeNotification item;
  final String time;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unread = item.unread;
    final category = item.category;
    final tint = switch (category) {
      NotificationCategory.requests => colors.primary,
      NotificationCategory.attendance => context.appColors.info,
      NotificationCategory.other => colors.onSurfaceVariant,
    };
    final VoidCallback? onTap =
        busy ? null : (item.opensTarget ? onOpen : (unread ? onMarkRead : null));
    return Material(
      color: unread
          ? colors.primaryContainer.withValues(alpha: 0.35)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: AppBorders.lg,
          side: BorderSide(
              color: unread
                  ? colors.primary.withValues(alpha: 0.4)
                  : colors.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: AppBorders.md),
                  child: Icon(notificationCategoryIcon(category), color: tint)),
              if (unread)
                PositionedDirectional(
                    top: -AppSpacing.xs,
                    end: -AppSpacing.xs,
                    child: Semantics(
                        label: 'notifications.unread'.tr(),
                        child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: colors.error,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: colors.surface, width: 2))))),
            ]),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(item.title,
                                style: context.textTheme.titleSmall?.copyWith(
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w500))),
                        SizedBox(width: AppSpacing.sm),
                        Text(time,
                            style: context.textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ]),
                  SizedBox(height: AppSpacing.xs),
                  Text(item.message,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(
                        child: Text(
                            item.needsAction
                                ? '${notificationCategoryKey(category).tr()} · ${'notifications.action_needed'.tr()}'
                                : notificationCategoryKey(category).tr(),
                            style: context.textTheme.labelMedium?.copyWith(
                                color: item.needsAction
                                    ? context.appColors.warning
                                    : tint,
                                fontWeight: item.needsAction
                                    ? FontWeight.w700
                                    : null))),
                    if (unread && item.opensTarget)
                      AppTextButton(
                          label: 'notifications.mark_read'.tr(),
                          onPressed: busy ? null : onMarkRead),
                    if (item.opensTarget)
                      Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          color: colors.onSurfaceVariant,
                          semanticLabel: 'notifications.open'.tr()),
                  ]),
                ])),
          ]),
        ),
      ),
    );
  }
}
