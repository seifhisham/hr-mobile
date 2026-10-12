import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../data/models/sales_activity.dart';
import '../data/repositories/sales_repository.dart';
import '../utils/utils.dart';

class SalesService implements SalesRepository {
  SalesService({Dio? client}) : _client = client;
  static final instance = SalesService();
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;
  @override
  FutureEither<SalesAccess> access() => runTask(
      () async => SalesAccess.fromJson(
          (await _dio.get<Map<String, dynamic>>('/sales/access')).data!),
      operation: 'sales.access',
      category: LogCategory.network);
  @override
  FutureEither<List<SalesActivity>> activities(String month,
          {bool team = false,
          String? kind,
          String? status,
          String? employeeId,
          String? department}) =>
      runTask(() async {
        final response = await _dio.get<List<dynamic>>(
            team ? '/sales/activities' : '/sales/activities/me',
            queryParameters: {
              'month': month,
              if (kind != null) 'kind': kind,
              if (status != null) 'status': status,
              if (employeeId != null) 'employeeId': employeeId,
              if (department != null) 'department': department
            });
        return response.data!
            .map((r) => SalesActivity.fromJson(r as Map<String, dynamic>))
            .toList();
      }, operation: 'sales.activities', category: LogCategory.network);
  @override
  FutureEither<List<SalesPerformance>> performance(String month,
          {bool team = false, String? employeeId, String? department}) =>
      runTask(() async {
        final response = await _dio.get<List<dynamic>>(
            team ? '/sales/performance' : '/sales/performance/me',
            queryParameters: {
              'month': month,
              if (team && employeeId != null) 'employeeId': employeeId,
              if (team && department != null) 'department': department
            });
        return response.data!
            .map((r) => SalesPerformance.fromJson(r as Map<String, dynamic>))
            .toList();
      }, operation: 'sales.performance', category: LogCategory.network);
  @override
  FutureEither<SalesActivity> activity(String id) => runTask(
      () async => SalesActivity.fromJson((await _dio.get<Map<String, dynamic>>(
              '/sales/activities/${Uri.encodeComponent(id)}'))
          .data!),
      operation: 'sales.activity',
      category: LogCategory.network);
  @override
  FutureEither<SalesActivity> create(String id, SalesSubmission input) =>
      runTask(
          () async => SalesActivity.fromJson((await _dio
                  .post<Map<String, dynamic>>('/sales/activities',
                      data: {'id': id, 'activity': input.toJson()}))
              .data!),
          operation: 'sales.create',
          category: LogCategory.network);
  @override
  FutureEither<SalesActivity> correct(
          String id, int revision, SalesSubmission input) =>
      runTask(
          () async => SalesActivity.fromJson((await _dio
                      .patch<Map<String, dynamic>>(
                          '/sales/activities/${Uri.encodeComponent(id)}',
                          data: {
                    'expectedRevision': revision,
                    'activity': input.toJson()
                  }))
                  .data!),
          operation: 'sales.correct',
          category: LogCategory.network);
  @override
  FutureEither<SalesActivity> review(
          String id, int revision, String status, String reason) =>
      runTask(
          () async => SalesActivity.fromJson((await _dio
                      .patch<Map<String, dynamic>>(
                          '/sales/activities/${Uri.encodeComponent(id)}/review',
                          data: {
                    'expectedRevision': revision,
                    'status': status,
                    'reason': reason.trim()
                  }))
                  .data!),
          operation: 'sales.review',
          category: LogCategory.network);
}
