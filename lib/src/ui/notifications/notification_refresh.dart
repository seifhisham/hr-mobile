import 'dart:async';
import 'package:hodour/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../requests/requests_provider.dart';
import '../../data/models/employee_request.dart';
import 'notifications_provider.dart';
import '../../services/push_notification_service.dart';
import '../../services/push_device_service.dart';

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
  StreamSubscription<bool>? _pushSubscription;
  bool _pushOpenPending = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _sync();
    _pushSubscription =
        PushNotificationService.instance.events.listen((opened) {
      if (!mounted) return;
      _pushOpenPending |= opened;
      _handlePush();
    });
    _pushOpenPending = PushNotificationService.instance.takePendingOpen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pushOpenPending) _handlePush();
    });
  }

  void _handlePush() {
    if (ref.read(sessionProvider).userOrNull == null) return;
    ref.read(notificationsProvider.notifier).refresh();
    if (!_pushOpenPending) return;
    _pushOpenPending = false;
    PushNotificationService.instance.takePendingOpen();
    ref.read(appRouterProvider).goNamed('notifications');
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
      PushDeviceService.instance.resume();
      ref.read(notificationsProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationsProvider);
    ref.listen(sessionProvider.select((s) => s.userOrNull?.sessionIdentity),
        (previous, next) {
      _sync();
      if (previous != null && previous != next) {
        _pushOpenPending = false;
        PushNotificationService.instance.takePendingOpen();
      }
      if (_pushOpenPending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handlePush();
        });
      }
    });
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
