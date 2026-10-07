import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/attendance_model.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../services/attendance_service.dart';
import '../../services/attendance_capture_service.dart';
import '../auth/providers/session_provider.dart';

final attendanceRepositoryProvider =
    Provider<AttendanceRepository>((ref) => AttendanceService.instance);
final attendanceCaptureProvider = Provider<AttendanceCaptureService>(
    (ref) => AttendanceCaptureService.instance);
final attendanceProvider =
    StateNotifierProvider<AttendanceController, AttendanceState>((ref) {
  // Dispose all personal state on sign-out/account change, including pending work.
  final identity = ref.watch(sessionProvider.select((s) =>
      (userId: s.userOrNull?.id, employeeId: s.userOrNull?.employee?.id)));
  return AttendanceController(ref.read(attendanceRepositoryProvider),
      ref.read(attendanceCaptureProvider),
      enabled: identity.employeeId != null);
});

class AttendanceState {
  const AttendanceState(
      {this.data = const RequestInitial(),
      this.action = const RequestInitial(),
      this.noticeKey,
      this.pending});
  final RequestState<AttendanceSnapshot> data;
  final RequestState<void> action;
  final String? noticeKey;
  final PendingAttendance? pending;
  AttendanceSnapshot? get snapshot =>
      switch (data) { RequestSuccess(:final data) => data, _ => null };
  bool get busy => data.isLoading || action.isLoading;
}

class PendingAttendance {
  const PendingAttendance(this.workDate, this.checkOutId);
  final String workDate;
  final String? checkOutId;
  bool completed(AttendanceSnapshot snapshot) => checkOutId == null
      ? snapshot.records.any((r) => r.workDate == workDate)
      : snapshot.records.any((r) => r.id == checkOutId && r.checkOut != null);
}

class AttendanceController extends StateNotifier<AttendanceState> {
  AttendanceController(this.repository, this.captureService,
      {bool enabled = true})
      : super(const AttendanceState()) {
    if (enabled) refresh();
  }
  final AttendanceRepository repository;
  final AttendanceCaptureService captureService;

  Future<void> refresh() async {
    if (state.busy) return;
    final pending = state.pending;
    state = AttendanceState(data: const RequestLoading(), pending: pending);
    final result = await repository.load();
    if (!mounted) return;
    state = result.fold(
        (failure) => AttendanceState(
            data: RequestFailure(failure),
            pending: pending,
            noticeKey: pending == null ? null : 'attendance.outcome_unknown'),
        (snapshot) => AttendanceState(
            data: RequestSuccess(snapshot),
            noticeKey: pending == null
                ? null
                : pending.completed(snapshot)
                    ? 'attendance.confirmed'
                    : 'attendance.not_recorded'));
  }

  Future<void> submit() async {
    if (state.busy || state.pending != null || state.snapshot == null) return;
    state = AttendanceState(data: state.data, action: const RequestLoading());
    // Recheck server workday/open records before each fresh capture.
    final latest = await repository.load();
    if (!mounted) return;
    final snapshot = latest.fold((_) => null, (value) => value);
    if (snapshot == null) {
      state = latest.fold(
          (failure) => AttendanceState(data: RequestFailure(failure)),
          (_) => const AttendanceState());
      return;
    }
    if (!snapshot.canSubmit) {
      state = AttendanceState(data: RequestSuccess(snapshot));
      return;
    }
    state = AttendanceState(
        data: RequestSuccess(snapshot), action: const RequestLoading());
    final capture = await captureService.capture(snapshot.policy);
    if (!mounted) return;
    final evidence = capture.fold((_) => null, (value) => value);
    if (evidence == null) {
      state = capture.fold(
          (failure) => AttendanceState(
              data: RequestSuccess(snapshot), action: RequestFailure(failure)),
          (_) => AttendanceState(data: RequestSuccess(snapshot)));
      return;
    }
    if (DateTime.now().toUtc().difference(evidence.capturedAt).inSeconds >
        snapshot.policy.maxCaptureAgeSeconds) {
      state = AttendanceState(
          data: RequestSuccess(snapshot),
          action: const RequestFailure(
              CaptureFailure('attendance.capture_expired')));
      return;
    }
    final pending = PendingAttendance(snapshot.workDate, snapshot.current?.id);
    final result =
        await repository.submit(evidence, checkOutId: pending.checkOutId);
    if (!mounted) return;
    final failure = result.fold((f) => f, (_) => null);
    if (failure is ServerFailure &&
        failure.statusCode != null &&
        failure.statusCode! < 500) {
      state = AttendanceState(
          data: RequestSuccess(snapshot), action: RequestFailure(failure));
      return;
    }
    // Never reuse evidence or blindly resubmit after a lost/invalid response.
    final reconciled = await repository.load();
    if (!mounted) return;
    state = reconciled.fold(
        (refreshFailure) => AttendanceState(
            data: RequestFailure(refreshFailure),
            pending: pending,
            noticeKey: failure == null
                ? 'attendance.saved_refresh_failed'
                : 'attendance.outcome_unknown'),
        (fresh) => AttendanceState(
            data: RequestSuccess(fresh),
            noticeKey: failure == null
                ? 'attendance.saved'
                : pending.completed(fresh)
                    ? 'attendance.confirmed'
                    : 'attendance.not_recorded'));
  }
}
