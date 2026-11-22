import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hodour/src/data/models/admin_dashboard.dart';
import 'package:hodour/src/data/models/sales_activity.dart';
import 'package:hodour/src/data/repositories/admin_dashboard_repository.dart';
import 'package:hodour/src/ui/admin/admin_dashboard_provider.dart';
import 'package:hodour/src/utils/async_state.dart';
import 'package:hodour/src/utils/failure.dart';
import 'package:hodour/src/utils/typedefs.dart';

Map<String, dynamic> _row(String employee, String date, String status,
        {String? checkIn,
        String? checkOut,
        bool late = false,
        String department = 'Sales',
        num? hours,
        String? location}) =>
    {
      'id': checkIn == null ? null : '$employee-$date',
      'employeeId': employee,
      'name': 'Employee $employee',
      'department': department,
      'workDate': date,
      'checkIn': checkIn,
      'checkOut': checkOut,
      'status': status,
      'late': late,
      'hours': hours,
      'timezone': 'UTC',
      'nationalId': '',
      'location': location == null ? null : {'status': location},
    };

const _today = '2026-11-22';

List<AttendanceReportRow> _attendance() => [
      for (final json in [
        _row('a', _today, 'On time',
            checkIn: '2026-11-22T08:55:00Z', location: 'inside'),
        _row('b', _today, 'Late',
            checkIn: '2026-11-22T09:40:00Z', late: true, location: 'outside'),
        _row('c', _today, 'No record', department: 'Ops'),
        _row('d', _today, 'Approved leave', department: 'Ops'),
        _row('e', _today, 'Not scheduled'),
        _row('b', '2026-11-21', 'Late',
            checkIn: '2026-11-21T09:30:00Z',
            checkOut: '2026-11-21T17:00:00Z',
            late: true,
            hours: 7.5),
        _row('a', '2026-11-20', 'Missing check-out',
            checkIn: '2026-11-20T09:00:00Z'),
      ])
        AttendanceReportRow.fromJson(json)
    ];

List<WorkforceMember> _workforce() => [
      for (final (id, active, role, start) in [
        ('a', true, 'employee', '2025-01-01'),
        ('b', true, 'employee', '2026-11-03'),
        ('c', false, 'employee', '2024-05-01'),
        ('x', true, 'admin', '2026-11-01'),
      ])
        WorkforceMember(
            id: id,
            name: id,
            department: id == 'c' ? 'Ops' : 'Sales',
            role: role,
            startDate: start,
            active: active,
            salesEnabled: id == 'a')
    ];

void main() {
  test('workdaysEndingOn lists dates oldest first across month ends', () {
    expect(workdaysEndingOn('2026-12-02', 4),
        ['2026-11-29', '2026-11-30', '2026-12-01', '2026-12-02']);
  });

  test('dashboard derives today, attention and workforce figures', () {
    final data = AdminDashboard(
        today: _today,
        days: workdaysEndingOn(_today, 7),
        attendance: _attendance(),
        workforce: _workforce());
    final today = data.todaySnapshot;
    expect(today.scheduled, 4);
    expect(today.present, 2);
    expect(today.late, 1);
    expect(today.absent, 1);
    expect(today.onLeave, 1);
    expect(today.working, 2);
    // 2 present of 3 expected (4 scheduled minus 1 on leave).
    expect(today.attendanceRate, closeTo(2 / 3, 1e-9));
    expect(today.punctuality, 0.5);

    expect(data.notCheckedIn.map((r) => r.employeeId), ['c']);
    expect(data.lateToday.map((r) => r.employeeId), ['b']);
    expect(data.outsideZone.map((r) => r.employeeId), ['b']);
    expect(data.openPastVisits.map((r) => r.workDate), ['2026-11-20']);
    expect(data.frequentLate.single.employeeId, 'b');
    expect(data.frequentLate.single.count, 2);
    expect(data.averageHours, 7.5);

    expect(data.departments.map((d) => (d.name, d.present, d.expected)),
        [('Ops', 0, 1), ('Sales', 2, 2)]);
    expect(data.trend, hasLength(7));
    expect(data.trend.last.date, _today);

    // Admin accounts are excluded from the workforce.
    expect(data.workforce, hasLength(3));
    expect(data.activeEmployees, 2);
    expect(data.inactiveEmployees, 1);
    expect(data.newHiresThisMonth, 1);
    expect(data.salesEnabledCount, 1);
    expect(data.departmentCount, 1);
  });

  test('empty days report no rate instead of dividing by zero', () {
    final snapshot = DaySnapshot.of(_today, const []);
    expect(snapshot.attendanceRate, isNull);
    expect(snapshot.punctuality, isNull);
  });

  test('controller keeps the dashboard when optional sections fail', () async {
    final repository = _FakeRepository();
    final controller = AdminDashboardController(repository, today: _today);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final state = controller.state;
    expect(state, isA<RequestSuccess<AdminDashboard>>());
    final data = (state as RequestSuccess<AdminDashboard>).data;
    expect(data.pending, isNull);
    expect(data.sales, isNull);
    expect(repository.from, '2026-11-16');
    controller.dispose();
  });

  test('controller reports failure when attendance cannot load', () async {
    final controller = AdminDashboardController(
        _FakeRepository(failAttendance: true),
        today: _today);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isA<RequestFailure<AdminDashboard>>());
    controller.dispose();
  });

  test('controller stays idle for non-admin sessions', () async {
    final repository = _FakeRepository();
    final controller = AdminDashboardController(repository, today: null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isA<RequestInitial<AdminDashboard>>());
    expect(repository.from, isNull);
    controller.dispose();
  });
}

class _FakeRepository implements AdminDashboardRepository {
  _FakeRepository({this.failAttendance = false});
  final bool failAttendance;
  String? from;

  @override
  FutureEither<List<AttendanceReportRow>> attendance(
      String from, String to) async {
    this.from = from;
    return failAttendance
        ? left(const NetworkFailure('offline'))
        : right(_attendance());
  }

  @override
  FutureEither<List<WorkforceMember>> workforce() async => right(_workforce());

  @override
  FutureEither<PendingRequests> pendingRequests({int limit = 100}) async =>
      left(const ServerFailure('forbidden', statusCode: 403));

  @override
  FutureEither<List<SalesPerformance>> salesPerformance(String month) async =>
      left(const ServerFailure('forbidden', statusCode: 403));
}
