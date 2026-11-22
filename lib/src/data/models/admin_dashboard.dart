import 'package:equatable/equatable.dart';

import 'employee_request.dart';
import 'sales_activity.dart';

/// One employee-workday row from the company attendance report
/// (`GET /attendance`). Days without a visit arrive with a `No record`,
/// `Not scheduled` or `Approved …` status and no times.
class AttendanceReportRow extends Equatable {
  const AttendanceReportRow({
    required this.employeeId,
    required this.name,
    required this.department,
    required this.workDate,
    required this.status,
    required this.late,
    required this.timezone,
    this.id,
    this.employeeNumber,
    this.branchName,
    this.checkIn,
    this.checkOut,
    this.hours,
    this.locationStatus,
  });

  factory AttendanceReportRow.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    return AttendanceReportRow(
      id: json['id'] as String?,
      employeeId: json['employeeId'] as String,
      employeeNumber: json['employeeNumber'] as String?,
      name: json['name'] as String,
      department: json['department'] as String? ?? '',
      branchName: json['branchName'] as String?,
      workDate: json['workDate'] as String,
      checkIn: _date(json['checkIn']),
      checkOut: _date(json['checkOut']),
      status: json['status'] as String,
      late: json['late'] as bool? ?? false,
      hours: (json['hours'] as num?)?.toDouble(),
      timezone: json['timezone'] as String? ?? 'UTC',
      locationStatus: location is Map<String, dynamic>
          ? location['status'] as String?
          : null,
    );
  }

  final String? id;
  final String employeeId;
  final String? employeeNumber;
  final String name;
  final String department;
  final String? branchName;
  final String workDate;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String status;
  final bool late;
  final double? hours;
  final String timezone;

  /// `inside`, `outside`, `unavailable` or `auto-checked-out`.
  final String? locationStatus;

  bool get attended => checkIn != null;
  bool get working => checkIn != null && checkOut == null;
  bool get scheduled => status != 'Not scheduled';
  bool get onLeave => status.startsWith('Approved ');
  bool get absent => status == 'No record';

  @override
  List<Object?> get props => [
        id,
        employeeId,
        employeeNumber,
        name,
        department,
        branchName,
        workDate,
        checkIn,
        checkOut,
        status,
        late,
        hours,
        timezone,
        locationStatus
      ];
}

/// The fields of `GET /employees` the dashboard needs.
class WorkforceMember extends Equatable {
  const WorkforceMember({
    required this.id,
    required this.name,
    required this.department,
    required this.role,
    required this.startDate,
    required this.active,
    required this.salesEnabled,
  });

  factory WorkforceMember.fromJson(Map<String, dynamic> json) =>
      WorkforceMember(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        department: json['department'] as String? ?? '',
        role: json['role'] as String? ?? 'employee',
        startDate: json['startDate'] as String? ?? '',
        active: json['active'] as bool? ?? false,
        salesEnabled: json['salesEnabled'] as bool? ?? false,
      );

  final String id, name, department, role, startDate;
  final bool active, salesEnabled;

  @override
  List<Object?> get props =>
      [id, name, department, role, startDate, active, salesEnabled];
}

/// Pending requests page plus the server's total pending count.
class PendingRequests extends Equatable {
  const PendingRequests({required this.items, required this.total});
  final List<EmployeeRequest> items;
  final int total;
  @override
  List<Object?> get props => [items, total];
}

/// Attendance totals for one workday.
class DaySnapshot extends Equatable {
  const DaySnapshot({
    required this.date,
    required this.scheduled,
    required this.present,
    required this.late,
    required this.absent,
    required this.onLeave,
    required this.working,
    required this.missingCheckOut,
  });

  factory DaySnapshot.of(String date, Iterable<AttendanceReportRow> rows) {
    var scheduled = 0,
        present = 0,
        late = 0,
        absent = 0,
        onLeave = 0,
        working = 0,
        missing = 0;
    for (final row in rows) {
      if (row.workDate != date) continue;
      if (row.scheduled) scheduled++;
      if (row.attended) present++;
      if (row.late) late++;
      if (row.absent) absent++;
      if (row.onLeave) onLeave++;
      if (row.working) working++;
      if (row.status == 'Missing check-out') missing++;
    }
    return DaySnapshot(
      date: date,
      scheduled: scheduled,
      present: present,
      late: late,
      absent: absent,
      onLeave: onLeave,
      working: working,
      missingCheckOut: missing,
    );
  }

  final String date;
  final int scheduled, present, late, absent, onLeave, working, missingCheckOut;

  /// Share of expected staff (scheduled, not on leave) who checked in.
  double? get attendanceRate {
    final expected = scheduled - onLeave;
    return expected <= 0 ? null : (present / expected).clamp(0, 1).toDouble();
  }

  /// Share of arrivals that were on time.
  double? get punctuality =>
      present == 0 ? null : ((present - late) / present).clamp(0, 1).toDouble();

  @override
  List<Object?> get props => [
        date,
        scheduled,
        present,
        late,
        absent,
        onLeave,
        working,
        missingCheckOut
      ];
}

class DepartmentSnapshot extends Equatable {
  const DepartmentSnapshot(
      {required this.name,
      required this.expected,
      required this.present,
      required this.late});
  final String name;
  final int expected, present, late;
  double get rate => expected == 0 ? 0 : (present / expected).clamp(0, 1);
  @override
  List<Object?> get props => [name, expected, present, late];
}

/// An employee with repeated late arrivals in the loaded week.
class LateStreak extends Equatable {
  const LateStreak(
      {required this.employeeId,
      required this.name,
      required this.department,
      required this.count});
  final String employeeId, name, department;
  final int count;
  @override
  List<Object?> get props => [employeeId, name, department, count];
}

/// Everything shown on the admin dashboard, with derived figures computed
/// once here so widgets stay free of business logic.
class AdminDashboard extends Equatable {
  AdminDashboard({
    required this.today,
    required this.days,
    required List<AttendanceReportRow> attendance,
    required List<WorkforceMember> workforce,
    this.pending,
    this.sales,
  })  : attendance = List.unmodifiable(attendance),
        // Admin accounts are not part of the attendance workforce.
        workforce = List.unmodifiable(
            workforce.where((member) => member.role != 'admin'));

  /// Company calendar date (`yyyy-MM-dd`).
  final String today;

  /// Workdays in the loaded range, oldest first, ending with [today].
  final List<String> days;
  final List<AttendanceReportRow> attendance;
  final List<WorkforceMember> workforce;

  /// Null when the requests endpoint could not be loaded.
  final PendingRequests? pending;

  /// Null when the sales endpoint could not be loaded.
  final List<SalesPerformance>? sales;

  late final List<AttendanceReportRow> todayRows =
      List.unmodifiable(attendance.where((row) => row.workDate == today));

  late final DaySnapshot todaySnapshot = DaySnapshot.of(today, attendance);

  late final List<DaySnapshot> trend = List.unmodifiable(
      [for (final day in days) DaySnapshot.of(day, attendance)]);

  /// Today's attendance per department, weakest first.
  late final List<DepartmentSnapshot> departments = () {
    final totals = <String, (int, int, int)>{};
    for (final row in todayRows) {
      if (!row.scheduled || row.onLeave) continue;
      final name = row.department.isEmpty ? '—' : row.department;
      final (expected, present, late) = totals[name] ?? (0, 0, 0);
      totals[name] = (
        expected + 1,
        present + (row.attended ? 1 : 0),
        late + (row.late ? 1 : 0)
      );
    }
    final list = [
      for (final MapEntry(:key, :value) in totals.entries)
        DepartmentSnapshot(
            name: key, expected: value.$1, present: value.$2, late: value.$3)
    ]..sort((a, b) {
        final byRate = a.rate.compareTo(b.rate);
        return byRate != 0 ? byRate : a.name.compareTo(b.name);
      });
    return List<DepartmentSnapshot>.unmodifiable(list);
  }();

  late final List<AttendanceReportRow> notCheckedIn = _sorted(
      todayRows.where((row) => row.absent), (a, b) => a.name.compareTo(b.name));

  late final List<AttendanceReportRow> lateToday = _sorted(
      todayRows.where((row) => row.late),
      (a, b) => (b.checkIn ?? DateTime(0)).compareTo(a.checkIn ?? DateTime(0)));

  /// Employees currently checked in but reported outside the work zone.
  late final List<AttendanceReportRow> outsideZone = _sorted(
      todayRows.where((row) => row.working && row.locationStatus == 'outside'),
      (a, b) => a.name.compareTo(b.name));

  /// Visits from earlier days that were never closed.
  late final List<AttendanceReportRow> openPastVisits = _sorted(
      attendance.where((row) => row.workDate != today && row.working),
      (a, b) => b.workDate.compareTo(a.workDate));

  /// Employees late two or more times in the loaded range.
  late final List<LateStreak> frequentLate = () {
    final counts = <String, (AttendanceReportRow, int)>{};
    for (final row in attendance) {
      if (!row.late) continue;
      final (_, count) = counts[row.employeeId] ?? (row, 0);
      counts[row.employeeId] = (row, count + 1);
    }
    final list = [
      for (final (row, count) in counts.values)
        if (count >= 2)
          LateStreak(
              employeeId: row.employeeId,
              name: row.name,
              department: row.department,
              count: count)
    ]..sort((a, b) =>
        b.count != a.count ? b.count - a.count : a.name.compareTo(b.name));
    return List<LateStreak>.unmodifiable(list);
  }();

  /// Average completed hours per closed visit in the loaded range.
  late final double? averageHours = () {
    final hours = [
      for (final row in attendance)
        if (row.hours != null) row.hours!
    ];
    return hours.isEmpty ? null : hours.reduce((a, b) => a + b) / hours.length;
  }();

  late final int activeEmployees =
      workforce.where((member) => member.active).length;
  late final int inactiveEmployees = workforce.length - activeEmployees;
  late final int departmentCount = {
    for (final member in workforce)
      if (member.active && member.department.isNotEmpty) member.department
  }.length;
  late final int salesEnabledCount =
      workforce.where((m) => m.active && m.salesEnabled).length;
  late final int newHiresThisMonth = workforce
      .where((m) => m.startDate.startsWith(today.substring(0, 7)))
      .length;

  /// Pending requests grouped by type, largest group first.
  late final List<(String, int)> pendingByType = () {
    final counts = <String, int>{};
    for (final request in pending?.items ?? const <EmployeeRequest>[]) {
      counts[request.type] = (counts[request.type] ?? 0) + 1;
    }
    return List<(String, int)>.unmodifiable([
      for (final MapEntry(:key, :value) in counts.entries) (key, value)
    ]..sort((a, b) => b.$2 - a.$2));
  }();

  late final SalesTotals? salesTotals =
      sales == null ? null : SalesTotals.of(sales!);

  @override
  List<Object?> get props =>
      [today, days, attendance, workforce, pending, sales];
}

class SalesTotals extends Equatable {
  const SalesTotals(
      {required this.meetings,
      required this.deals,
      required this.pending,
      required this.returned,
      required this.top});

  factory SalesTotals.of(List<SalesPerformance> rows) {
    final ranked = [
      for (final row in rows)
        if (row.deals > 0 || row.meetingTotal > 0) row
    ]..sort((a, b) => b.deals != a.deals
        ? b.deals - a.deals
        : b.meetingTotal - a.meetingTotal);
    return SalesTotals(
      meetings: rows.fold(0, (sum, row) => sum + row.meetingTotal),
      deals: rows.fold(0, (sum, row) => sum + row.deals),
      pending: rows.fold(0, (sum, row) => sum + row.pending),
      returned: rows.fold(0, (sum, row) => sum + row.returned),
      top: List.unmodifiable(ranked.take(3)),
    );
  }

  final int meetings, deals, pending, returned;
  final List<SalesPerformance> top;

  @override
  List<Object?> get props => [meetings, deals, pending, returned, top];
}

List<T> _sorted<T>(Iterable<T> items, int Function(T, T) compare) =>
    List<T>.unmodifiable(items.toList()..sort(compare));

DateTime? _date(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.parse(value) : null;
