import 'dart:async';
import 'package:hrmobile/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../requests/requests_provider.dart';
import '../../data/models/employee_request.dart';
import 'notifications_provider.dart';

/// One foreground timer for the signed-in app, including when the inbox is closed.
class NotificationRefresh extends ConsumerStatefulWidget {
  const NotificationRefresh({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<NotificationRefresh> createState() =>
      _NotificationRefreshState();
}

class _NotificationRefreshState extends ConsumerState<NotificationRefresh>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!_foreground || ref.read(sessionProvider).userOrNull == null) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.read(notificationsProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (_foreground && ref.read(sessionProvider).userOrNull != null) {
      ref.read(notificationsProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationsProvider);
    ref.listen(sessionProvider.select((s) => s.userOrNull?.id),
        (previous, next) => _sync());
    ref.listen(requestsProvider, (previous, next) {
      if (next.action is RequestSuccess<EmployeeRequest> &&
          !identical(previous?.action, next.action) &&
          _foreground &&
          ref.read(sessionProvider).userOrNull != null) {
        ref.read(notificationsProvider.notifier).refresh(afterMutation: true);
      }
    });
    ref.listen(managedRequestsProvider, (previous, next) {
      if (next.action is RequestSuccess<EmployeeRequest> &&
          !identical(previous?.action, next.action) &&
          _foreground &&
          ref.read(sessionProvider).userOrNull != null) {
        ref.read(notificationsProvider.notifier).refresh(afterMutation: true);
      }
    });
    return widget.child;
  }
}
