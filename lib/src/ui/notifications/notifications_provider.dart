import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/employee_notification.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../services/notifications_service.dart';
import '../auth/providers/session_provider.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsService.instance);
final notificationsProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  final identity = ref.watch(sessionProvider
      .select((s) => (s.userOrNull?.id, s.userOrNull?.employee?.id)));
  return NotificationsController(ref.read(notificationsRepositoryProvider),
      enabled: identity.$1 != null);
});

class NotificationsState {
  const NotificationsState({
    this.data = const RequestInitial(),
    this.previous,
    this.action = const RequestInitial(),
    this.noticeKey,
  });
  final RequestState<NotificationInbox> data;
  final NotificationInbox? previous;
  final RequestState<void> action;
  final String? noticeKey;
  NotificationInbox? get inbox => switch (data) {
        RequestSuccess(:final data) => data,
        _ => previous,
      };
  bool get busy => data.isLoading || action.isLoading;
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this.repository, {bool enabled = true})
      : super(const NotificationsState()) {
    if (enabled) refresh();
  }
  final NotificationsRepository repository;
  bool _refreshAfterLoad = false;

  Future<void> refresh({bool afterMutation = false}) async {
    if (state.busy) {
      if (afterMutation) _refreshAfterLoad = true;
      return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final previous = state.inbox;
    final action = state.action;
    final notice = state.noticeKey;
    state = NotificationsState(
        data: const RequestLoading(),
        previous: previous,
        action: action,
        noticeKey: notice);
    final result = await repository.load();
    if (!mounted) return;
    state = result.fold(
        (failure) => NotificationsState(
            data: RequestFailure(failure),
            previous: failure is ServerFailure &&
                    (failure.statusCode == 401 || failure.statusCode == 403)
                ? null
                : previous,
            action: action,
            noticeKey: notice),
        (inbox) => NotificationsState(
            data: RequestSuccess(inbox), action: action, noticeKey: notice));
    if (_refreshAfterLoad) {
      _refreshAfterLoad = false;
      await refresh();
    }
  }

  Future<bool> markRead(String id) async {
    if (state.busy) return false;
    final item = state.inbox?.items.where((item) => item.id == id).firstOrNull;
    if (item == null) return false;
    if (!item.unread) return true;
    state = NotificationsState(
        data: state.data,
        previous: state.previous,
        action: const RequestLoading());
    final result = await repository.markRead(id);
    if (!mounted) return false;
    final success = result.fold((failure) {
      state = NotificationsState(
          data: state.data,
          previous: state.previous,
          action: RequestFailure(failure),
          noticeKey: failure is ServerFailure && failure.statusCode == 404
              ? 'notifications.removed'
              : null);
      return false;
    }, (_) {
      state = NotificationsState(
          data: state.data,
          previous: state.previous,
          action: const RequestSuccess(null));
      return true;
    });
    await _refresh();
    return mounted && success;
  }
}
