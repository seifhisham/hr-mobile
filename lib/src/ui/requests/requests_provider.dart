import 'package:hodour/src/imports/imports.dart';
import '../../data/models/employee_request.dart';
import '../../data/repositories/requests_repository.dart';
import '../../services/requests_service.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_provider.dart';

final requestsRepositoryProvider =
    Provider<RequestsRepository>((ref) => RequestsService.instance);
final requestsProvider =
    StateNotifierProvider<RequestsController, RequestsState>((ref) {
  final identity = ref.watch(sessionProvider.select(
      (s) => (s.userOrNull?.sessionIdentity, s.userOrNull?.employee?.id)));
  return RequestsController(ref.read(requestsRepositoryProvider),
      enabled: identity.$2 != null,
      onChanged: () =>
          ref.read(attendanceProvider.notifier).refresh(afterMutation: true));
});

final managedRequestsProvider =
    StateNotifierProvider<RequestsController, RequestsState>((ref) {
  final identity = ref.watch(sessionProvider.select(
      (s) => (s.userOrNull?.sessionIdentity, s.userOrNull?.employee?.id)));
  return RequestsController(ref.read(requestsRepositoryProvider),
      enabled: identity.$2 != null, managed: true, employeeId: identity.$2);
});

sealed class PendingRequestMutation {
  const PendingRequestMutation();
}

final class PendingRequestCreation extends PendingRequestMutation {
  const PendingRequestCreation(this.input, this.previousIds);
  final RequestSubmission input;
  final Set<String> previousIds;
}

final class PendingRequestWithdrawal extends PendingRequestMutation {
  const PendingRequestWithdrawal(this.id);
  final String id;
}

final class PendingManagerReview extends PendingRequestMutation {
  const PendingManagerReview(
      this.id, this.status, this.reason, this.employeeId);
  final String id, status, reason, employeeId;
}

class RequestsState {
  const RequestsState(
      {this.data = const RequestInitial(),
      this.action = const RequestInitial(),
      this.previousItems,
      this.pending,
      this.noticeKey});
  final RequestState<List<EmployeeRequest>> data;
  final RequestState<EmployeeRequest> action;
  final List<EmployeeRequest>? previousItems;
  final PendingRequestMutation? pending;
  final String? noticeKey;
  List<EmployeeRequest> get items => switch (data) {
        RequestSuccess(:final data) => data,
        _ => previousItems ?? []
      };
  bool get busy => data.isLoading || action.isLoading;
}

class RequestsController extends StateNotifier<RequestsState> {
  RequestsController(this.repository,
      {bool enabled = true,
      this.managed = false,
      this.employeeId,
      this.onChanged})
      : super(const RequestsState()) {
    if (enabled) refresh();
  }
  final RequestsRepository repository;
  final Future<void> Function()? onChanged;
  final bool managed;
  final String? employeeId;
  Future<void>? _refreshing;
  Future<void> refresh() async {
    if (_refreshing case final pending?) {
      await pending;
      return;
    }
    if (state.busy) return;
    final wasLoaded = state.data.isSuccess;
    final previousItems = state.items;
    await _refresh();
    if (mounted &&
        wasLoaded &&
        state.data.isSuccess &&
        !listEquals(previousItems, state.items)) {
      await onChanged?.call();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing case final pending?) {
      await pending;
      return;
    }
    final pending = _load();
    _refreshing = pending;
    try {
      await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _load() async {
    final previousState = state;
    final pending = state.pending;
    final action = state.action;
    final notice = state.noticeKey;
    if (!state.data.isSuccess) {
      state = RequestsState(
          data: const RequestLoading(),
          previousItems: state.previousItems,
          action: action,
          pending: pending,
          noticeKey: notice);
    }
    final result =
        await (managed ? repository.loadManaged() : repository.load());
    if (!mounted) return;
    result.fold((failure) {
      state = RequestsState(
          data: RequestFailure(failure),
          previousItems: failure is ServerFailure &&
                  (failure.statusCode == 401 || failure.statusCode == 403)
              ? null
              : previousState.items,
          action: action,
          pending: pending,
          noticeKey: pending == null ? notice : 'requests.reconcile_required');
    }, (items) {
      if (pending == null &&
          previousState.data.isSuccess &&
          listEquals(previousState.items, items)) {
        return;
      }
      final confirmed = switch (pending) {
        PendingRequestCreation(:final input, :final previousIds) => items
            .where(
                (item) => !previousIds.contains(item.id) && item.matches(input))
            .firstOrNull,
        PendingRequestWithdrawal(:final id) => items
            .where((item) => item.id == id && item.status == 'withdrawn')
            .firstOrNull,
        PendingManagerReview(
          :final id,
          :final status,
          :final reason,
          :final employeeId
        ) =>
          items
              .where((item) =>
                  item.id == id &&
                  item.managerStage == status &&
                  item.managerReview?.status == status &&
                  item.managerReview?.reason == reason &&
                  item.managerReview?.employeeId == employeeId)
              .firstOrNull,
        null => null,
      };
      state = RequestsState(
          data: RequestSuccess(items),
          action: confirmed == null ? action : RequestSuccess(confirmed),
          noticeKey: pending == null
              ? notice
              : confirmed != null
                  ? 'requests.confirmed'
                  : 'requests.not_confirmed');
    });
  }

  void clearAction() {
    if (state.busy || _refreshing != null || state.pending != null) return;
    state = RequestsState(data: state.data);
  }

  Future<void> submit(RequestSubmission input) async {
    if (_refreshing case final pending?) await pending;
    if (!mounted) return;
    if (managed ||
        state.busy ||
        state.pending != null ||
        state.data is! RequestSuccess<List<EmployeeRequest>>) {
      return;
    }
    final pending =
        PendingRequestCreation(input, state.items.map((r) => r.id).toSet());
    state = RequestsState(data: state.data, action: const RequestLoading());
    final result = await repository.submit(input);
    if (!mounted) return;
    await _finish(result, pending);
  }

  Future<void> withdraw(EmployeeRequest item, String reason) async {
    if (_refreshing case final pending?) await pending;
    if (!mounted) return;
    if (managed ||
        state.busy ||
        state.pending != null ||
        !item.canWithdraw ||
        state.data is! RequestSuccess<List<EmployeeRequest>>) {
      return;
    }
    if (reason.trim().length < 5 || reason.trim().length > 500) return;
    state = RequestsState(data: state.data, action: const RequestLoading());
    final result = await repository.withdraw(item.id, reason);
    if (!mounted) return;
    await _finish(result, PendingRequestWithdrawal(item.id));
  }

  Future<void> review(
      EmployeeRequest item, String status, String reason) async {
    if (_refreshing case final pending?) await pending;
    if (!mounted) return;
    final current = state.items.where((r) => r.id == item.id).firstOrNull;
    final trimmed = reason.trim();
    if (!managed ||
        state.busy ||
        state.pending != null ||
        current == null ||
        state.data is! RequestSuccess<List<EmployeeRequest>> ||
        state.noticeKey == 'requests.review_unavailable' ||
        !current.canReview(employeeId) ||
        !const ['approved', 'rejected'].contains(status) ||
        trimmed.length < 5 ||
        trimmed.length > 500) {
      return;
    }
    state = RequestsState(data: state.data, action: const RequestLoading());
    final result = await repository.review(current.id, status, trimmed);
    if (!mounted) return;
    await _finish(
        result, PendingManagerReview(current.id, status, trimmed, employeeId!));
  }

  Future<void> _finish(Either<Failure, EmployeeRequest> result,
      PendingRequestMutation pending) async {
    state = result.fold(
        (failure) => RequestsState(
            data: state.data,
            action: RequestFailure(failure),
            pending: _uncertain(failure) ? pending : null,
            noticeKey: pending is PendingManagerReview &&
                    failure is ServerFailure &&
                    const [403, 404, 409].contains(failure.statusCode)
                ? 'requests.review_unavailable'
                : _uncertain(failure)
                    ? 'requests.reconcile_required'
                    : null),
        (item) => RequestsState(
            data: state.data,
            action: RequestSuccess(item),
            noticeKey: 'requests.saved'));
    await _refresh();
    if (mounted) await onChanged?.call();
  }

  bool _uncertain(Failure failure) => switch (failure) {
        ServerFailure(:final statusCode)
            when statusCode != null && statusCode >= 400 && statusCode < 500 =>
          false,
        _ => true,
      };
}
