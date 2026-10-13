import 'dart:async';
import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/attendance_location.dart';
import '../../data/models/attendance_model.dart';
import '../../services/attendance_location_source.dart';
import '../../services/attendance_service.dart';
import '../../services/attendance_location_warning.dart';
import '../auth/providers/session_provider.dart';
import 'attendance_provider.dart';

final attendanceLocationWarningProvider =
    Provider((ref) => AttendanceLocationWarning.instance);
final attendanceLocationSourceProvider =
    Provider((ref) => AttendanceLocationSource.instance);
final attendanceLocationServiceProvider =
    Provider((ref) => AttendanceService.instance);
final attendanceMonitorProvider =
    StateNotifierProvider<AttendanceMonitor, AttendanceMonitorState>((ref) {
  final identity = ref.watch(sessionProvider.select((s) =>
      (userId: s.userOrNull?.id, employeeId: s.userOrNull?.employee?.id)));
  final monitor = AttendanceMonitor(ref.read(attendanceLocationSourceProvider),
      ref.read(attendanceLocationServiceProvider),
      reconcile: () => ref.read(attendanceProvider.notifier).refresh());
  if (identity.employeeId != null) {
    ref.listen(attendanceProvider, (_, next) {
      if (next.data case RequestSuccess<AttendanceSnapshot>(:final data)) {
        monitor.sync(data);
      }
    }, fireImmediately: true);
  }
  return monitor;
});

class AttendanceMonitorState {
  const AttendanceMonitorState(
      {this.record, this.policy, this.location, this.failure});
  final AttendanceRecord? record;
  final AttendanceTrackingPolicy? policy;
  final AttendanceLocation? location;
  final Failure? failure;
}

class AttendanceMonitor extends StateNotifier<AttendanceMonitorState> {
  AttendanceMonitor(this.source, this.service, {required this.reconcile})
      : super(const AttendanceMonitorState());
  final AttendanceLocationSource source;
  final AttendanceService service;
  final Future<void> Function() reconcile;
  StreamSubscription<AttendanceLocationFix>? _positions;
  Future<void>? _stopping;
  Timer? _timer;
  CancelToken? _request;
  int _generation = 0;
  bool _busy = false, _starting = false, _unauthorized = false;
  bool _unavailablePending = false;
  DateTime? _lastAttempt, _lastCapture;

  void sync(AttendanceSnapshot snapshot) {
    if (!mounted || _unauthorized) return;
    final open = snapshot.open;
    final policy = snapshot.policy.tracking;
    if (open?.id != state.record?.id || policy != state.policy) {
      _stop();
      _lastCapture = open?.location?.lastCapturedAt;
      state = AttendanceMonitorState(
          record: open, policy: policy, location: open?.location);
      if (open != null && policy != null) {
        _timer = Timer.periodic(Duration(seconds: policy.updateIntervalSeconds),
            (_) {
          if (_positions == null && !_starting) {
            start();
          } else {
            report();
          }
        });
        unawaited(start());
      }
    } else {
      state = AttendanceMonitorState(
          record: open,
          policy: policy,
          location: open?.location,
          failure: state.failure);
      final serverCapture = open?.location?.lastCapturedAt;
      if (serverCapture != null &&
          (_lastCapture == null || serverCapture.isAfter(_lastCapture!))) {
        _lastCapture = serverCapture;
      }
    }
  }

  Future<void> start() async {
    if (!mounted ||
        state.record == null ||
        state.policy == null ||
        _starting ||
        _positions != null) {
      return;
    }
    final generation = _generation;
    _starting = true;
    try {
      await _stopping;
      if (!_valid(generation)) return;
      await source.checkAccess();
      if (!_valid(generation)) return;
      _positions = source.positions(state.policy!).listen((fix) {
        if (!_valid(generation)) return;
        // Drop while busy, never enqueue fixes. Throttle using upload attempts,
        // not GPS timestamps; a stationary device still gets fresh timed captures.
        if (_lastAttempt == null ||
            DateTime.now().difference(_lastAttempt!) >=
                Duration(seconds: state.policy!.updateIntervalSeconds)) {
          unawaited(report(fix: fix));
        }
      }, onError: (Object error) {
        if (_valid(generation)) {
          _stopping = _positions?.cancel();
          _positions = null;
          unawaited(report(unavailable: true));
        }
      }, onDone: () {
        if (_valid(generation)) _positions = null;
      });
    } catch (error) {
      if (_valid(generation)) {
        _setFailure(Failure.fromException(error));
      }
    } finally {
      if (_valid(generation)) _starting = false;
    }
    if (_valid(generation)) await report();
  }

  Future<void> enable() async {
    final generation = _generation;
    if (state.record == null || state.policy == null) return;
    try {
      await source.requestAccess();
      if (!_valid(generation)) return;
      await start();
      if (_valid(generation)) await report();
    } catch (error) {
      if (_valid(generation)) _setFailure(Failure.fromException(error));
    }
  }

  Future<void> report(
      {AttendanceLocationFix? fix, bool unavailable = false}) async {
    if (!mounted ||
        _unauthorized ||
        state.record == null ||
        state.policy == null) {
      return;
    }
    if (_busy) {
      // Keep loss of access, never coordinates, for the next serialized request.
      if (unavailable) _unavailablePending = true;
      return;
    }
    final generation = _generation;
    final id = state.record!.id;
    final policy = state.policy!;
    _busy = true;
    _lastAttempt = DateTime.now();
    Failure? acquisitionFailure;
    try {
      if (!unavailable && fix == null) {
        try {
          fix = await source.capture();
        } catch (error) {
          acquisitionFailure = Failure.fromException(error);
        }
      }
      if (!_valid(generation)) return;
      if (fix != null &&
          !fix.isFresh(DateTime.now().toUtc(), policy, _lastCapture)) {
        fix = null;
        acquisitionFailure = const CaptureFailure('tracking.fresh_unavailable');
      }
      if (fix != null) _lastCapture = fix.capturedAt;
      if (fix == null) _unavailablePending = false;
      _request = CancelToken();
      final result =
          await service.reportLocation(id, fix, cancelToken: _request);
      if (!_valid(generation)) return;
      final failure = result.fold((f) => f, (_) => null);
      if (failure case ServerFailure(statusCode: 401)) {
        _unauthorized = true;
        _stop();
        state = const AttendanceMonitorState();
        return;
      }
      final location = result.fold((_) => null, (value) => value);
      if (location?.status == 'auto-checked-out' ||
          location?.autoCheckedOutAt != null) {
        _stop();
        state = const AttendanceMonitorState();
        await reconcile();
        return;
      }
      state = result.fold(
          (f) => AttendanceMonitorState(
              record: state.record,
              policy: policy,
              location: state.location,
              failure: f),
          (location) => AttendanceMonitorState(
              record: state.record,
              policy: policy,
              location: location,
              failure: acquisitionFailure ??
                  (unavailable
                      ? const CaptureFailure('tracking.fresh_unavailable')
                      : null)));
      // Read back after accepted writes and conflicts. Never retry a rejected fix.
      if (failure == null && !_unavailablePending ||
          failure is ServerFailure &&
              (failure.statusCode == 409 || failure.statusCode == 404)) {
        await reconcile();
      }
    } finally {
      if (_valid(generation)) {
        _busy = false;
        _request = null;
        if (_unavailablePending) {
          _unavailablePending = false;
          await report(unavailable: true);
        }
      }
    }
  }

  bool _valid(int generation) => mounted && generation == _generation;
  void _setFailure(Failure failure) => state = AttendanceMonitorState(
      record: state.record,
      policy: state.policy,
      location: state.location,
      failure: failure);
  void _stop() {
    _generation++;
    _request?.cancel();
    _request = null;
    _stopping = _positions?.cancel() ?? _stopping;
    _positions = null;
    _timer?.cancel();
    _timer = null;
    _busy = false;
    _unavailablePending = false;
    _starting = false;
    _lastAttempt = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
