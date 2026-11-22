import '../models/admin_dashboard.dart';
import '../models/sales_activity.dart';
import '../../utils/utils.dart';

/// Company-wide figures for admin accounts.
abstract class AdminDashboardRepository {
  /// Attendance report rows for every employee between [from] and [to]
  /// (inclusive company calendar dates, at most 93 days).
  FutureEither<List<AttendanceReportRow>> attendance(String from, String to);
  FutureEither<List<WorkforceMember>> workforce();

  /// The newest pending requests and the total pending count.
  FutureEither<PendingRequests> pendingRequests({int limit = 100});
  FutureEither<List<SalesPerformance>> salesPerformance(String month);
}
