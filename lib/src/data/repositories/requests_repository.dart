import '../models/employee_request.dart';
import '../../utils/utils.dart';

abstract class RequestsRepository {
  FutureEither<List<EmployeeRequest>> load();
  FutureEither<List<EmployeeRequest>> loadManaged();
  FutureEither<EmployeeRequest> submit(RequestSubmission input);
  FutureEither<EmployeeRequest> review(String id, String status, String reason);
  FutureEither<EmployeeRequest> withdraw(String id, String reason);
}
