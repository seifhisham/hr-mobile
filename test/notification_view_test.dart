import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/models/employee_notification.dart';
import 'package:hodour/src/ui/notifications/notification_view.dart';
import 'package:timezone/data/latest.dart' as tzdata;

EmployeeNotification _item(
  String id, {
  String createdAt = '2026-11-18T10:00:00Z',
  bool read = false,
  String? requestId,
  String? attendanceId,
  String type = 'request-decided',
}) =>
    EmployeeNotification.fromJson({
      'id': id,
      'type': type,
      'title': 'Title $id',
      'message': 'Message $id',
      'createdAt': createdAt,
      'readAt': read ? '2026-11-18T10:05:00Z' : null,
      'requestId': requestId,
      'attendanceId': attendanceId,
    });

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final items = [
    _item('a', requestId: 'r1'),
    _item('b', read: true, requestId: 'r2'),
    _item('c', attendanceId: 'at1'),
    _item('d', read: true),
  ];

  test('category follows what the notification links to', () {
    expect(items.map((i) => i.category), [
      NotificationCategory.requests,
      NotificationCategory.requests,
      NotificationCategory.attendance,
      NotificationCategory.other,
    ]);
    expect(items[3].opensTarget, isFalse);
    expect(items[2].opensTarget, isTrue);
  });

  test('status and category filters combine and keep server order', () {
    expect(filterNotifications(items).map((i) => i.id), ['a', 'b', 'c', 'd']);
    expect(
        filterNotifications(items, status: NotificationStatusFilter.unread)
            .map((i) => i.id),
        ['a', 'c']);
    expect(
        filterNotifications(items,
                status: NotificationStatusFilter.unread,
                category: NotificationCategory.requests)
            .map((i) => i.id),
        ['a']);
    expect(
        filterNotifications(items, category: NotificationCategory.other)
            .map((i) => i.id),
        ['d']);
  });

  test('needs-action keeps only approval requests and combines with others',
      () {
    final withReviews = [
      ...items,
      _item('e', requestId: 'r3', type: 'manager-review-required'),
      _item('f',
          read: true, requestId: 'r4', type: 'manager-review-required'),
    ];
    expect(withReviews.where((i) => i.needsAction).map((i) => i.id), ['e', 'f']);
    expect(
        filterNotifications(withReviews, needsAction: true).map((i) => i.id),
        ['e', 'f']);
    expect(
        filterNotifications(withReviews,
                needsAction: true, status: NotificationStatusFilter.unread)
            .map((i) => i.id),
        ['e']);
    expect(
        filterNotifications(withReviews,
                needsAction: true, category: NotificationCategory.attendance)
            .map((i) => i.id),
        isEmpty);
  });

  test('category counts only include categories that occur', () {
    final unread =
        filterNotifications(items, status: NotificationStatusFilter.unread);
    expect(categoryCounts(unread), {
      NotificationCategory.requests: 1,
      NotificationCategory.attendance: 1,
    });
  });

  test('days are bucketed in the employee timezone, not UTC', () {
    // 23:30 UTC on the 17th is already the 18th in Cairo (UTC+2).
    final now = DateTime.utc(2026, 11, 18, 12);
    expect(
        notificationDay(
            DateTime.utc(2026, 11, 17, 23, 30), now, 'Africa/Cairo'),
        NotificationDay.today);
    expect(notificationDay(DateTime.utc(2026, 11, 17, 23, 30), now, 'UTC'),
        NotificationDay.yesterday);
    expect(notificationDay(DateTime.utc(2026, 11, 10, 9), now, 'UTC'),
        NotificationDay.earlier);
    expect(notificationDay(DateTime.utc(2026, 11, 17, 9), now, 'Not/AZone'),
        NotificationDay.yesterday);
  });

  test('grouping keeps order, skips empty days and formats times', () {
    final now = DateTime.utc(2026, 11, 18, 12);
    final grouped = groupNotificationsByDay([
      _item('today', createdAt: '2026-11-18T09:30:00Z'),
      _item('old', createdAt: '2026-11-01T08:00:00Z'),
    ], now, 'UTC');
    expect(grouped.map((g) => g.$1),
        [NotificationDay.today, NotificationDay.earlier]);
    expect(grouped.first.$2.single.id, 'today');
    expect(notificationTime(DateTime.utc(2026, 11, 18, 9, 30), now, 'UTC'),
        '09:30');
    expect(notificationTime(DateTime.utc(2026, 11, 1, 8), now, 'UTC'),
        '1 Nov, 08:00');
  });
}
