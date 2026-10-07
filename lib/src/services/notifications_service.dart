import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../data/models/employee_notification.dart';
import '../data/repositories/notifications_repository.dart';
import '../utils/utils.dart';

class NotificationsService implements NotificationsRepository {
  NotificationsService({Dio? client}) : _client = client;
  static final instance = NotificationsService();
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;

  @override
  FutureEither<NotificationInbox> load() => runTask(() async {
        final response = await _dio.get<Map<String, dynamic>>('/notifications');
        return NotificationInbox.fromJson(response.data!);
      }, operation: 'notifications.load', category: LogCategory.network);

  @override
  FutureEither<EmployeeNotification> markRead(String id) => runTask(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
            '/notifications/${Uri.encodeComponent(id)}/read');
        return EmployeeNotification.fromJson(response.data!);
      }, operation: 'notifications.read', category: LogCategory.network);
}
