import '../models/sales_activity.dart';
import '../../utils/utils.dart';

abstract class SalesRepository {
  FutureEither<SalesAccess> access();
  FutureEither<List<SalesActivity>> activities(String month,
      {bool team = false,
      String? kind,
      String? status,
      String? employeeId,
      String? department});
  FutureEither<List<SalesPerformance>> performance(String month,
      {bool team = false, String? employeeId, String? department});
  FutureEither<SalesActivity> activity(String id);
  FutureEither<SalesActivity> create(String id, SalesSubmission input);
  FutureEither<SalesActivity> correct(
      String id, int revision, SalesSubmission input);
  FutureEither<SalesActivity> review(
      String id, int revision, String status, String reason);
}
