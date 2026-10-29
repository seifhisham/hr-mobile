import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/utils.dart';
import 'attendance_location_source.dart';
import 'push_notification_service.dart';

class AttendanceLocationWarning {
  static final instance = AttendanceLocationWarning();
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  int _revision = 0;
  static const _id = 150;

  Future<void> _initialize() {
    if (PushNotificationService.supported) {
      return PushNotificationService.instance.initializeLocalNotifications();
    }
    return _initializing ??= _plugin
        .initialize(
            settings: const InitializationSettings(
                android: AndroidInitializationSettings('ic_attendance'),
                iOS: DarwinInitializationSettings(
                    requestAlertPermission: false,
                    requestBadgePermission: false,
                    requestSoundPermission: false)))
        .then((_) {});
  }

  Future<bool> requestPermission() async {
    if (!AttendanceLocationSource.supported) return false;
    try {
      await _initialize();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return (await android?.requestNotificationsPermission() ??
          await ios?.requestPermissions(alert: true, sound: true) ??
          false);
    } catch (error) {
      AppLogger.warning('Attendance notification permission unavailable',
          context: {'type': error.runtimeType.toString()});
      return false;
    }
  }

  Future<void> update(DateTime? deadline, {String? title, String? message}) {
    final revision = ++_revision;
    // Serialize native calls too: a late show must never outlive cancellation.
    _queue = _queue.then((_) async {
      if (!AttendanceLocationSource.supported) return;
      try {
        await _initialize();
        if (revision != _revision) return;
        if (deadline == null || !deadline.isAfter(DateTime.now())) {
          await _plugin.cancel(id: _id);
        } else {
          await _plugin.show(
              id: _id,
              title: title,
              body: message,
              notificationDetails: const NotificationDetails(
                  android: AndroidNotificationDetails(
                      'attendance_return', 'Attendance return warning',
                      importance: Importance.high, priority: Priority.high),
                  iOS: DarwinNotificationDetails(
                      presentAlert: true, presentSound: true)));
        }
      } catch (error) {
        AppLogger.warning('Attendance warning unavailable',
            context: {'type': error.runtimeType.toString()});
      }
    });
    return _queue;
  }
}
