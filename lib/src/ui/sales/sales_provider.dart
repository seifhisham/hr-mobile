import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/sales_service.dart';
import '../auth/providers/session_provider.dart';

final salesRepositoryProvider =
    Provider<SalesRepository>((ref) => SalesService.instance);
final salesAccessProvider =
    StateNotifierProvider<SalesAccessController, RequestState<SalesAccess>>(
        (ref) {
  final identity = ref.watch(sessionProvider.select((s) => s.userOrNull?.id));
  return SalesAccessController(ref.read(salesRepositoryProvider),
      enabled: identity != null);
});

class SalesAccessController extends StateNotifier<RequestState<SalesAccess>> {
  SalesAccessController(this.repository, {required bool enabled})
      : super(const RequestInitial()) {
    if (enabled) refresh();
  }
  final SalesRepository repository;
  int _generation = 0;
  Future<void> refresh() async {
    final generation = ++_generation;
    final previous = state;
    if (!previous.isSuccess) state = const RequestLoading();
    final result = await repository.access();
    if (!mounted || generation != _generation) return;
    result.fold((failure) {
      if (!previous.isSuccess ||
          failure is ServerFailure &&
              (failure.statusCode == 401 || failure.statusCode == 403)) {
        state = RequestFailure(failure);
      }
    }, (value) {
      if (previous is! RequestSuccess<SalesAccess> || previous.data != value) {
        state = RequestSuccess(value);
      }
    });
  }
}

SalesAccess accessValue(RequestState<SalesAccess> state) => switch (state) {
      RequestSuccess(:final data) => data,
      _ => const SalesAccess(),
    };

class SalesDashboard extends Equatable {
  const SalesDashboard(this.activities, this.performance);
  final List<SalesActivity> activities;
  final List<SalesPerformance> performance;
  @override
  List<Object?> get props => [activities, performance];
}

class SalesListState {
  const SalesListState(
      {required this.month,
      this.kind,
      this.status,
      this.employeeId,
      this.previousDashboard,
      this.data = const RequestInitial()});
  final String month;
  final String? kind, status, employeeId;
  final RequestState<SalesDashboard> data;
  final SalesDashboard? previousDashboard;
  SalesDashboard? get dashboard => switch (data) {
        RequestSuccess(:final data) => data,
        _ => previousDashboard,
      };
}

final salesListProvider =
    StateNotifierProvider.family<SalesListController, SalesListState, bool>(
        (ref, team) {
  final identity = ref.watch(sessionProvider
      .select((s) => (s.userOrNull?.id, s.userOrNull?.employee?.id)));
  final month =
      ref.read(sessionProvider).userOrNull?.today.substring(0, 7) ?? '2000-01';
  final controller = SalesListController(ref.read(salesRepositoryProvider),
      month: month,
      team: team,
      enabled: identity.$1 != null &&
          (team
              ? accessValue(ref.read(salesAccessProvider)).canReview
              : identity.$2 != null),
      onForbidden: () => ref.read(salesAccessProvider.notifier).refresh());
  ref.listen(salesMutationProvider.select((s) => s.epoch),
      (_, next) => controller.refresh());
  ref.listen(salesAccessProvider, (previous, next) {
    if (team && next is RequestSuccess<SalesAccess>) {
      controller.setEnabled(next.data.canReview);
    }
  });
  return controller;
});

class SalesListController extends StateNotifier<SalesListState> {
  SalesListController(this.repository,
      {required String month,
      required this.team,
      required bool enabled,
      required this.onForbidden})
      : _enabled = enabled,
        super(SalesListState(month: month)) {
    if (enabled) refresh();
  }
  final SalesRepository repository;
  final bool team;
  final Future<void> Function() onForbidden;
  bool _enabled;
  int _generation = 0;
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      refresh();
    } else {
      _generation++;
      state = SalesListState(month: state.month);
    }
  }

  Future<void> filter(
      {String? month, String? kind, String? status, String? employeeId}) async {
    if (!mounted || !_enabled) return;
    if (month != null && !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      return;
    }
    state = SalesListState(
        month: month ?? state.month,
        kind: kind,
        status: status,
        employeeId: employeeId);
    await refresh();
  }

  Future<void> refresh() async {
    if (!_enabled || !mounted) return;
    final generation = ++_generation;
    final query = state;
    if (query.dashboard == null) {
      state = SalesListState(
          month: query.month,
          kind: query.kind,
          status: query.status,
          employeeId: query.employeeId,
          data: const RequestLoading());
    }
    // These independent reads intentionally run together.
    final activities = repository.activities(query.month,
        team: team,
        kind: query.kind,
        status: query.status,
        employeeId: query.employeeId);
    final performance = repository.performance(query.month, team: team);
    final activityResult = await activities;
    final performanceResult = await performance;
    if (!mounted || generation != _generation) return;
    final failure = activityResult.fold<Failure?>((f) => f, (_) => null) ??
        performanceResult.fold<Failure?>((f) => f, (_) => null);
    if (failure is ServerFailure && failure.statusCode == 403) {
      await onForbidden();
    }
    if (!mounted || generation != _generation) return;
    final dashboard = failure == null
        ? SalesDashboard(activityResult.getOrElse((_) => []),
            performanceResult.getOrElse((_) => []))
        : null;
    if (query.data.isSuccess &&
        dashboard != null &&
        dashboard == query.dashboard) {
      return;
    }
    state = SalesListState(
        month: query.month,
        kind: query.kind,
        status: query.status,
        employeeId: query.employeeId,
        previousDashboard: failure is ServerFailure &&
                (failure.statusCode == 401 || failure.statusCode == 403)
            ? null
            : query.dashboard,
        data: failure != null
            ? RequestFailure(failure)
            : RequestSuccess(dashboard!));
  }
}

sealed class SalesPendingMutation {
  const SalesPendingMutation(this.id);
  final String id;
}

final class SalesPendingCreate extends SalesPendingMutation {
  const SalesPendingCreate(super.id, this.input, {this.retryAllowed = false});
  final SalesSubmission input;
  final bool retryAllowed;
}

final class SalesPendingCorrection extends SalesPendingMutation {
  const SalesPendingCorrection(super.id, this.revision, this.input);
  final int revision;
  final SalesSubmission input;
}

final class SalesPendingReview extends SalesPendingMutation {
  const SalesPendingReview(super.id, this.revision, this.status, this.reason);
  final int revision;
  final String status, reason;
}

class SalesMutationState {
  const SalesMutationState(
      {this.action = const RequestInitial(),
      this.pending,
      this.notice,
      this.epoch = 0});
  final RequestState<SalesActivity> action;
  final SalesPendingMutation? pending;
  final String? notice;
  final int epoch;
}

final salesMutationProvider =
    StateNotifierProvider<SalesMutationController, SalesMutationState>((ref) {
  final identity = ref.watch(sessionProvider
      .select((s) => (s.userOrNull?.id, s.userOrNull?.employee?.id)));
  return SalesMutationController(ref.read(salesRepositoryProvider),
      employeeId: identity.$2,
      getAccess: () => accessValue(ref.read(salesAccessProvider)),
      onForbidden: () => ref.read(salesAccessProvider.notifier).refresh());
});

class SalesMutationController extends StateNotifier<SalesMutationState> {
  SalesMutationController(this.repository,
      {required this.employeeId,
      required this.getAccess,
      required this.onForbidden})
      : super(const SalesMutationState());
  final SalesRepository repository;
  final String? employeeId;
  final SalesAccess Function() getAccess;
  final Future<void> Function() onForbidden;
  void clear() {
    if (!state.action.isLoading && state.pending == null) {
      state = SalesMutationState(epoch: state.epoch);
    }
  }

  void editUnstoredCreation() {
    if (state.action.isLoading) return;
    if (state.pending case SalesPendingCreate(retryAllowed: true)) {
      state = SalesMutationState(epoch: state.epoch);
    }
  }

  Future<void> create(SalesSubmission input) async {
    if (state.action.isLoading ||
        state.pending != null ||
        !getAccess().canSubmit ||
        employeeId == null) {
      return;
    }
    final pending = SalesPendingCreate(newSalesId(), input);
    state = SalesMutationState(
        action: const RequestLoading(), pending: pending, epoch: state.epoch);
    await _finish(await repository.create(pending.id, input), pending);
  }

  Future<void> correct(SalesActivity item, SalesSubmission input) async {
    if (state.action.isLoading ||
        state.pending != null ||
        !getAccess().canSubmit ||
        !item.canCorrect(employeeId)) {
      return;
    }
    final pending = SalesPendingCorrection(item.id, item.revision, input);
    state = SalesMutationState(
        action: const RequestLoading(), pending: pending, epoch: state.epoch);
    await _finish(
        await repository.correct(item.id, item.revision, input), pending);
  }

  Future<void> review(SalesActivity item, String status, String reason) async {
    final trimmed = reason.trim();
    if (state.action.isLoading ||
        state.pending != null ||
        !getAccess().canReview ||
        trimmed.length < 5 ||
        trimmed.length > 500 ||
        !(status == 'verified'
            ? item.canVerify(employeeId)
            : status == 'returned' && item.canReturn(employeeId))) {
      return;
    }
    final pending = SalesPendingReview(item.id, item.revision, status, trimmed);
    state = SalesMutationState(
        action: const RequestLoading(), pending: pending, epoch: state.epoch);
    await _finish(
        await repository.review(item.id, item.revision, status, trimmed),
        pending);
  }

  Future<void> retryCreation() async {
    final pending = state.pending;
    if (state.action.isLoading ||
        pending is! SalesPendingCreate ||
        !pending.retryAllowed ||
        !getAccess().canSubmit) {
      return;
    }
    state = SalesMutationState(
        action: const RequestLoading(), pending: pending, epoch: state.epoch);
    await _finish(await repository.create(pending.id, pending.input), pending);
  }

  Future<void> _finish(Either<Failure, SalesActivity> result,
      SalesPendingMutation pending) async {
    if (!mounted) return;
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure == null) {
      state = SalesMutationState(
          action: RequestSuccess(
              result.getOrElse((_) => throw StateError('Missing activity'))),
          notice: 'sales.saved',
          epoch: state.epoch + 1);
      return;
    }
    if (failure is ServerFailure && failure.statusCode == 403) {
      await onForbidden();
    }
    if (!mounted) return;
    final uncertain = switch (failure) {
      ServerFailure(:final statusCode)
          when statusCode != null && statusCode >= 400 && statusCode < 500 =>
        false,
      _ => true,
    };
    state = SalesMutationState(
        action: RequestFailure(failure),
        pending: uncertain ? pending : null,
        notice: uncertain ? 'sales.reconcile_required' : null,
        epoch: state.epoch);
    if (uncertain) {
      await reconcile();
    } else if (failure is ServerFailure && failure.statusCode == 409) {
      // Refresh details and summaries before a deliberate new action.
      await repository.activity(pending.id);
      if (mounted) {
        state = SalesMutationState(
            action: RequestFailure(failure),
            notice: 'sales.changed',
            epoch: state.epoch + 1);
      }
    }
  }

  Future<void> reconcile() async {
    final pending = state.pending;
    if (pending == null || state.action.isLoading) return;
    state = SalesMutationState(
        action: const RequestLoading(),
        pending: pending,
        notice: 'sales.reconcile_required',
        epoch: state.epoch);
    final result = await repository.activity(pending.id);
    if (!mounted) return;
    result.fold((failure) {
      final missing = failure is ServerFailure && failure.statusCode == 404;
      state = SalesMutationState(
          action: RequestFailure(failure),
          epoch: state.epoch,
          pending: missing && pending is SalesPendingCreate
              ? SalesPendingCreate(pending.id, pending.input,
                  retryAllowed: true)
              : pending,
          notice: missing && pending is SalesPendingCreate
              ? 'sales.retry_same'
              : 'sales.reconcile_required');
      if (failure is ServerFailure && failure.statusCode == 403) onForbidden();
    }, (item) {
      final confirmed = switch (pending) {
        SalesPendingCreate() => item.employeeId == employeeId,
        SalesPendingCorrection(:final revision, :final input) =>
          item.revision == revision + 1 &&
              item.status == 'pending' &&
              item.supported &&
              _samePayload(item.submission, input),
        SalesPendingReview(:final revision, :final status, :final reason) =>
          item.revision == revision + 1 &&
              item.status == status &&
              item.review?.status == status &&
              item.review?.reason == reason,
      };
      state = SalesMutationState(
          action: confirmed ? RequestSuccess(item) : const RequestInitial(),
          notice: confirmed ? 'sales.confirmed' : 'sales.changed',
          epoch: state.epoch + 1);
    });
  }

  bool _samePayload(SalesSubmission a, SalesSubmission b) {
    final left = a.toJson(), right = b.toJson();
    return left.length == right.length &&
        left.entries.every((e) => right[e.key] == e.value);
  }
}

final salesDetailProvider = FutureProvider.autoDispose
    .family<Either<Failure, SalesActivity>, String>((ref, id) {
  ref.watch(sessionProvider.select((s) => s.userOrNull?.id));
  ref.watch(salesMutationProvider.select((s) => s.epoch));
  return ref.read(salesRepositoryProvider).activity(id);
});
