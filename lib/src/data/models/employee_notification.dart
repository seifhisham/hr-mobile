class EmployeeNotification {
  EmployeeNotification.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        type = json['type'] as String,
        title = json['title'] as String,
        message = json['message'] as String,
        createdAt = DateTime.parse(json['createdAt'] as String),
        readAt = json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
        requestId = json['requestId'] as String?,
        attendanceId = json['attendanceId'] as String?;

  final String id, type, title, message;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? requestId, attendanceId;
  bool get unread => readAt == null;
}

class NotificationInbox {
  NotificationInbox.fromJson(Map<String, dynamic> json)
      : items = (json['items'] as List)
            .map((item) =>
                EmployeeNotification.fromJson(item as Map<String, dynamic>))
            .toList(),
        unreadCount = json['unreadCount'] as int;
  final List<EmployeeNotification> items;
  final int unreadCount;
}
