import 'package:hodour/src/imports/imports.dart';
import 'notifications_provider.dart';

class NotificationButton extends ConsumerWidget {
  const NotificationButton({super.key, this.color, this.dotBadge = false});
  final Color? color;
  final bool dotBadge;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (GoRouterState.of(context).name == 'notifications') {
      return const SizedBox.shrink();
    }
    final state = ref.watch(notificationsProvider);
    final count =
        state.data is RequestFailure ? null : state.inbox?.unreadCount;
    final label = count == null
        ? 'notifications.title'.tr()
        : 'notifications.unread_count'.tr(namedArgs: {'count': '$count'});
    final button = AppIconButton(
      color: color,
      tooltip: 'notifications.title'.tr(),
      icon: Icons.notifications_none_rounded,
      onPressed: () => context.pushNamed('notifications'),
    );
    return Semantics(
      label: label,
      button: true,
      liveRegion: true,
      onTap: () => context.pushNamed('notifications'),
      excludeSemantics: true,
      child: (count ?? 0) > 0
          ? dotBadge
              ? Badge(backgroundColor: context.colors.error, child: button)
              : AppBadge(label: count! > 99 ? '99+' : '$count', child: button)
          : button,
    );
  }
}
