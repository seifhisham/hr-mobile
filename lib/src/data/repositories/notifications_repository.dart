import '../models/employee_notification.dart';
import '../../utils/utils.dart';

abstract class NotificationsRepository {
  FutureEither<NotificationInbox> load();
  FutureEither<EmployeeNotification> markRead(String id);
}
