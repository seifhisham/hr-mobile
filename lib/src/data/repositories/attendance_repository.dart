import '../../utils/utils.dart';
import '../models/attendance_model.dart';

abstract class AttendanceRepository {
  FutureEither<AttendanceSnapshot> load();
  FutureEither<AttendanceRecord> submit(AttendanceCapture capture,
      {String? checkOutId});
}
