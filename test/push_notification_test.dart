import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hodour/src/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('push tap is queued once and attendance taps are ignored', () async {
    final service = PushNotificationService();
    final events = <bool>[];
    final subscription = service.events.listen(events.add);
    addTearDown(subscription.cancel);
    service.handleLocalResponse(const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotification));
    expect(service.takePendingOpen(), false);
    service.handleLocalResponse(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'fcm'));
    await Future<void>.delayed(Duration.zero);
    expect(events, [true]);
    expect(service.takePendingOpen(), true);
    expect(service.takePendingOpen(), false);
  });
}
