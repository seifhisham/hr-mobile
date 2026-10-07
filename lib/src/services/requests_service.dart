import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../data/models/employee_request.dart';
import '../data/repositories/requests_repository.dart';
import '../utils/utils.dart';

class RequestsService implements RequestsRepository {
  RequestsService({Dio? client}) : _client = client;
  static final instance = RequestsService();
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;
  @override
  FutureEither<List<EmployeeRequest>> loadManaged() => runTask(() async {
        final response = await _dio.get<List<dynamic>>('/requests/managed');
        return response.data!
            .map((r) => EmployeeRequest.fromJson(r as Map<String, dynamic>))
            .toList();
      }, operation: 'requests.managed', category: LogCategory.network);
  @override
  FutureEither<List<EmployeeRequest>> load() => runTask(() async {
        final response = await _dio.get<List<dynamic>>('/requests/me');
        return response.data!
            .map((r) => EmployeeRequest.fromJson(r as Map<String, dynamic>))
            .toList();
      }, operation: 'requests.load', category: LogCategory.network);
  @override
  FutureEither<EmployeeRequest> submit(RequestSubmission input) =>
      runTask(() async {
        final response = await _dio.post<Map<String, dynamic>>('/requests',
            data: input.toJson());
        return EmployeeRequest.fromJson(response.data!);
      }, operation: 'requests.submit', category: LogCategory.network);
  @override
  FutureEither<EmployeeRequest> withdraw(String id, String reason) =>
      runTask(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
            '/requests/${Uri.encodeComponent(id)}/withdraw',
            data: {'reason': reason.trim()});
        return EmployeeRequest.fromJson(response.data!);
      }, operation: 'requests.withdraw', category: LogCategory.network);
}
