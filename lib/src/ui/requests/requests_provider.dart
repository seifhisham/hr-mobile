import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/employee_request.dart';
import '../../data/repositories/requests_repository.dart';
import '../../services/requests_service.dart';
import '../auth/providers/session_provider.dart';

final requestsRepositoryProvider =
    Provider<RequestsRepository>((ref) => RequestsService.instance);
final requestsProvider =
    StateNotifierProvider<RequestsController, RequestsState>((ref) {
  final identity = ref.watch(sessionProvider
      .select((s) => (s.userOrNull?.id, s.userOrNull?.employee?.id)));
  return RequestsController(ref.read(requestsRepositoryProvider),
      enabled: identity.$2 != null);
});

final managedRequestsProvider =
    StateNotifierProvider<RequestsController, RequestsState>((ref) {
  final identity = ref.watch(sessionProvider
      .select((s) => (s.userOrNull?.id, s.userOrNull?.employee?.id)));
  return RequestsController(ref.read(requestsRepositoryProvider),
      enabled: identity.$2 != null, managed: true);
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

class RequestsState {
  const RequestsState(
      {this.data = const RequestInitial(),
      this.action = const RequestInitial(),
      this.pending,
      this.noticeKey});
  final RequestState<List<EmployeeRequest>> data;
  final RequestState<EmployeeRequest> action;
  final PendingRequestMutation? pending;
  final String? noticeKey;
  List<EmployeeRequest> get items =>
      switch (data) { RequestSuccess(:final data) => data, _ => [] };
  bool get busy => data.isLoading || action.isLoading;
}

class RequestsController extends StateNotifier<RequestsState> {
  RequestsController(this.repository,
      {bool enabled = true, this.managed = false})
      : super(const RequestsState()) {
    if (enabled) refresh();
  }
  final RequestsRepository repository;
  final bool managed;
  Future<void>? _refreshing;
  Future<void> refresh() async {
    if (_refreshing case final pending?) {
      await pending;
      return;
    }
    if (state.busy) return;
    await _refresh();
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
    final pending = state.pending;
    final action = state.action;
    final notice = state.noticeKey;
    state = RequestsState(
        data: const RequestLoading(),
        action: action,
        pending: pending,
        noticeKey: notice);
    final result =
        await (managed ? repository.loadManaged() : repository.load());
    if (!mounted) return;
    result.fold((failure) {
      state = RequestsState(
          data: RequestFailure(failure),
          action: action,
          pending: pending,
          noticeKey: pending == null ? notice : 'requests.reconcile_required');
    }, (items) {
      final confirmed = switch (pending) {
        PendingRequestCreation(:final input, :final previousIds) => items
            .where(
                (item) => !previousIds.contains(item.id) && item.matches(input))
            .firstOrNull,
        PendingRequestWithdrawal(:final id) => items
            .where((item) => item.id == id && item.status == 'withdrawn')
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
    if (state.busy || state.pending != null) return;
    state = RequestsState(data: state.data);
  }

  Future<void> submit(RequestSubmission input) async {
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

  Future<void> _finish(Either<Failure, EmployeeRequest> result,
      PendingRequestMutation pending) async {
    state = result.fold(
        (failure) => RequestsState(
            data: state.data,
            action: RequestFailure(failure),
            pending: _uncertain(failure) ? pending : null,
            noticeKey:
                _uncertain(failure) ? 'requests.reconcile_required' : null),
        (item) => RequestsState(
            data: state.data,
            action: RequestSuccess(item),
            noticeKey: 'requests.saved'));
    await _refresh();
  }

  bool _uncertain(Failure failure) => switch (failure) {
        ServerFailure(:final statusCode)
            when statusCode != null && statusCode >= 400 && statusCode < 500 =>
          false,
        _ => true,
      };
}
