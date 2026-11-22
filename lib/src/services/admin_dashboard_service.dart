import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../data/models/admin_dashboard.dart';
import '../data/models/employee_request.dart';
import '../data/models/sales_activity.dart';
import '../data/repositories/admin_dashboard_repository.dart';
import '../utils/utils.dart';

class AdminDashboardService implements AdminDashboardRepository {
  AdminDashboardService({Dio? client}) : _client = client;
  static final instance = AdminDashboardService();
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;

  @override
  FutureEither<List<AttendanceReportRow>> attendance(String from, String to) =>
      runTask(() async {
        final response = await _dio.get<List<dynamic>>('/attendance',
            queryParameters: {'from': from, 'to': to});
        return response.data!
            .map((r) => AttendanceReportRow.fromJson(r as Map<String, dynamic>))
            .toList();
      },
          operation: 'adminDashboard.attendance',
          category: LogCategory.network,
          context: {'from': from, 'to': to});

  @override
  FutureEither<List<WorkforceMember>> workforce() => runTask(() async {
        final response = await _dio.get<List<dynamic>>('/employees');
        return response.data!
            .map((r) => WorkforceMember.fromJson(r as Map<String, dynamic>))
            .toList();
      }, operation: 'adminDashboard.workforce', category: LogCategory.network);

  @override
  FutureEither<PendingRequests> pendingRequests({int limit = 100}) =>
      runTask(() async {
        final response = await _dio.get<List<dynamic>>('/requests',
            queryParameters: {'status': 'pending', 'limit': limit});
        final items = response.data!
            .map((r) => EmployeeRequest.fromJson(r as Map<String, dynamic>))
            .toList();
        final total =
            int.tryParse(response.headers.value('x-total-count') ?? '');
        return PendingRequests(items: items, total: total ?? items.length);
      }, operation: 'adminDashboard.pending', category: LogCategory.network);

  @override
  FutureEither<List<SalesPerformance>> salesPerformance(String month) =>
      runTask(() async {
        final response = await _dio.get<List<dynamic>>('/sales/performance',
            queryParameters: {'month': month});
        return response.data!
            .map((r) => SalesPerformance.fromJson(r as Map<String, dynamic>))
            .toList();
      }, operation: 'adminDashboard.sales', category: LogCategory.network);
}
