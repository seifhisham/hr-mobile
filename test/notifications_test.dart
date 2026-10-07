import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hrmobile/src/data/models/employee_notification.dart';
import 'package:hrmobile/src/data/repositories/notifications_repository.dart';
import 'package:hrmobile/src/services/notifications_service.dart';
import 'package:hrmobile/src/ui/notifications/notifications_provider.dart';
import 'package:hrmobile/src/utils/utils.dart';
import 'auth_session_test.dart' show TestAdapter, jsonResponse;

Map<String, dynamic> notificationJson(
        {String id = 'manager-pending:event/opaque ?',
        String? readAt,
        String type = 'request-decided'}) =>
    {
      'id': id,
      'type': type,
      'title': 'Request approved',
      'message': 'Annual leave approved by HR',
      'createdAt': '2026-10-06T10:00:00Z',
      'readAt': readAt,
      'requestId': 'request-1',
    };

class _Notifications implements NotificationsRepository {
  List<Either<Failure, NotificationInbox>> loads = [];
  Either<Failure, EmployeeNotification>? result;
  Completer<void>? wait;
  int reads = 0;
  @override
  FutureEither<NotificationInbox> load() async {
    await wait?.future;
    return loads.removeAt(0);
  }

  @override
  FutureEither<EmployeeNotification> markRead(String id) async {
    reads++;
    return result!;
  }
}

NotificationInbox _inbox(List<Map<String, dynamic>> items, int count) =>
    NotificationInbox.fromJson({'items': items, 'unreadCount': count});

void main() {
  test(
      'a mutation during an in-flight poll refreshes again after the old result',
      () async {
    final wait = Completer<void>();
    final repository = _Notifications()
      ..wait = wait
      ..loads = [
        right(_inbox([], 0)),
        right(_inbox([notificationJson()], 1))
      ];
    final controller = NotificationsController(repository, enabled: false);
    addTearDown(controller.dispose);
    final oldPoll = controller.refresh();
    await controller.refresh(afterMutation: true);
    wait.complete();
    await oldPoll;
    expect(controller.state.inbox!.unreadCount, 1);
    expect(repository.loads, isEmpty);
  });

  test('REST preserves opaque IDs, server count and original read timestamp',
      () async {
    final calls = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3002/api'));
    addTearDown(() => client.close(force: true));
    client.httpClientAdapter = TestAdapter((request) {
      calls.add(request);
      return jsonResponse(request.method == 'GET'
          ? {
              'items': [notificationJson()],
              'unreadCount': 7
            }
          : notificationJson(readAt: '2026-10-06T10:01:00Z'));
    });
    final service = NotificationsService(client: client);
    final inbox = (await service.load()).getOrElse((f) => throw f);
    expect(inbox.unreadCount, 7);
    final first = (await service.markRead(inbox.items.single.id))
        .getOrElse((f) => throw f);
    final second = (await service.markRead(first.id)).getOrElse((f) => throw f);
    expect(second.readAt, first.readAt);
    expect(calls.first.path, '/notifications');
    expect(calls[1].path,
        '/notifications/manager-pending%3Aevent%2Fopaque%20%3F/read');
    expect(calls[1].method, 'PATCH');
    expect(calls[1].data, isNull);
  });

  test('removed notifications refresh away and read errors remain recoverable',
      () async {
    final repository = _Notifications()
      ..loads = [
        right(_inbox([notificationJson()], 1)),
        right(_inbox([], 0))
      ]
      ..result = left(const ServerFailure('Gone', statusCode: 404));
    final controller = NotificationsController(repository, enabled: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(await controller.markRead(controller.state.inbox!.items.single.id),
        false);
    expect(controller.state.inbox!.items, isEmpty);
    expect(controller.state.noticeKey, 'notifications.removed');
    expect(repository.reads, 1);
  });

  test('read items do not send another PATCH; auth failures drop cached data',
      () async {
    final repository = _Notifications()
      ..loads = [
        right(_inbox([notificationJson(readAt: '2026-10-06T10:01:00Z')], 0)),
        left(const ServerFailure('Expired', statusCode: 401)),
      ];
    final controller = NotificationsController(repository, enabled: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(await controller.markRead(controller.state.inbox!.items.single.id),
        true);
    expect(repository.reads, 0);
    await controller.refresh();
    expect(controller.state.inbox, isNull);
  });

  test('a late load cannot restore private notifications after disposal',
      () async {
    final wait = Completer<void>();
    final repository = _Notifications()
      ..wait = wait
      ..loads = [
        right(_inbox([notificationJson()], 1))
      ];
    final controller = NotificationsController(repository, enabled: false);
    final pending = controller.refresh();
    controller.dispose();
    wait.complete();
    await pending;
    expect(repository.loads, isEmpty);
  });
}
