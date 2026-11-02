import 'attendance_model.dart';

class AttendanceTotals {
  const AttendanceTotals._(this.completedTime, this.visits, this.lateArrivals);

  final Duration completedTime;
  final int visits, lateArrivals;

  factory AttendanceTotals.fromRecords(List<AttendanceRecord> records) {
    var completedTime = Duration.zero;
    var lateArrivals = 0;
    for (final record in records) {
      if (record.checkOut case final checkOut?) {
        completedTime += record.elapsedAt(checkOut);
      }
      if (record.status == 'Late') lateArrivals++;
    }
    return AttendanceTotals._(completedTime, records.length, lateArrivals);
  }
}
