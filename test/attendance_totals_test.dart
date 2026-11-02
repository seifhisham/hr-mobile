import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/data/models/attendance_totals.dart';
import 'attendance_test.dart' show recordJson;

void main() {
  test(
      'totals use completed intervals and server lateness, excluding open time',
      () {
    final records = [
      AttendanceRecord.fromJson(recordJson(closed: true)),
      AttendanceRecord.fromJson({
        ...recordJson(closed: true),
        'id': 'late',
        'checkIn': '2026-10-05T22:30:00Z',
        'status': 'Late',
      }),
      AttendanceRecord.fromJson({...recordJson(), 'id': 'open'}),
    ];
    final totals = AttendanceTotals.fromRecords(records);
    expect(totals.completedTime, const Duration(hours: 11, minutes: 30));
    expect(totals.visits, 3);
    expect(totals.lateArrivals, 1);
    final filtered =
        AttendanceTotals.fromRecords(filterAttendance(records, status: 'Late'));
    expect(filtered.completedTime, const Duration(hours: 5, minutes: 30));
    expect(filtered.visits, 1);
    expect(filtered.lateArrivals, 1);
  });

  test('empty records have zero totals; invalid negative time is not added',
      () {
    final empty = AttendanceTotals.fromRecords([]);
    expect(empty.completedTime, Duration.zero);
    expect(empty.visits, 0);
    expect(empty.lateArrivals, 0);
    final invalid = AttendanceRecord.fromJson({
      ...recordJson(closed: true),
      'checkOut': '2026-10-05T21:00:00Z',
    });
    expect(
        AttendanceTotals.fromRecords([invalid]).completedTime, Duration.zero);
  });
}
