import 'package:hodour/src/imports/imports.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/employee_notification.dart';

/// Which read state the inbox is narrowed to.
enum NotificationStatusFilter { all, unread }

/// What a notification is about, derived from what it links to.
enum NotificationCategory { requests, attendance, other }

/// Day bucket used to group the inbox into sections.
enum NotificationDay { today, yesterday, earlier }

extension EmployeeNotificationView on EmployeeNotification {
  NotificationCategory get category {
    if (requestId != null) return NotificationCategory.requests;
    if (attendanceId != null) return NotificationCategory.attendance;
    return NotificationCategory.other;
  }

  bool get opensTarget => requestId != null || attendanceId != null;

  /// A request waiting for this employee's review or approval.
  bool get needsAction => type == 'manager-review-required';
}

/// Applies the status, category and needs-action filters, keeping the
/// server order.
List<EmployeeNotification> filterNotifications(
  List<EmployeeNotification> items, {
  NotificationStatusFilter status = NotificationStatusFilter.all,
  NotificationCategory? category,
  bool needsAction = false,
}) =>
    items
        .where((item) =>
            (status == NotificationStatusFilter.all || item.unread) &&
            (category == null || item.category == category) &&
            (!needsAction || item.needsAction))
        .toList();

/// How many items fall in each category (only categories that occur).
Map<NotificationCategory, int> categoryCounts(
    List<EmployeeNotification> items) {
  final counts = <NotificationCategory, int>{};
  for (final item in items) {
    counts.update(item.category, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

DateTime _inZone(DateTime value, String timezone) {
  try {
    final zoned = tz.TZDateTime.from(value, tz.getLocation(timezone));
    return DateTime(
        zoned.year, zoned.month, zoned.day, zoned.hour, zoned.minute);
  } on tz.LocationNotFoundException {
    final utc = value.toUtc();
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }
}

NotificationDay notificationDay(
    DateTime createdAt, DateTime now, String timezone) {
  final created = _inZone(createdAt, timezone);
  final today = _inZone(now, timezone);
  final createdDay = DateTime(created.year, created.month, created.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final difference = todayDay.difference(createdDay).inDays;
  if (difference <= 0) return NotificationDay.today;
  if (difference == 1) return NotificationDay.yesterday;
  return NotificationDay.earlier;
}

/// Groups items by day, preserving order and omitting empty days.
List<(NotificationDay, List<EmployeeNotification>)> groupNotificationsByDay(
    List<EmployeeNotification> items, DateTime now, String timezone) {
  final buckets = {
    for (final day in NotificationDay.values) day: <EmployeeNotification>[]
  };
  for (final item in items) {
    buckets[notificationDay(item.createdAt, now, timezone)]!.add(item);
  }
  return [
    for (final day in NotificationDay.values)
      if (buckets[day]!.isNotEmpty) (day, buckets[day]!),
  ];
}

/// Short time label: just the clock time for today and yesterday,
/// otherwise the date as well.
String notificationTime(DateTime createdAt, DateTime now, String timezone) {
  final created = _inZone(createdAt, timezone);
  final day = notificationDay(createdAt, now, timezone);
  return day == NotificationDay.earlier
      ? DateFormat('d MMM, HH:mm').format(created)
      : DateFormat('HH:mm').format(created);
}
