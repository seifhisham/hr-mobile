import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../data/models/attendance_model.dart';
import '../data/repositories/attendance_repository.dart';
import '../utils/utils.dart';

class AttendanceService implements AttendanceRepository {
  AttendanceService({Dio? client}) : _client = client;
  static final instance = AttendanceService();
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;
  @override
  FutureEither<AttendanceSnapshot> load() => runTask(() async {
        final me = await _dio.get<Map<String, dynamic>>('/attendance/me');
        final policy =
            await _dio.get<Map<String, dynamic>>('/attendance/policy');
        return AttendanceSnapshot.fromJson(
            me.data!, AttendancePolicy.fromJson(policy.data!));
      }, operation: 'attendance.load', category: LogCategory.network);
  @override
  FutureEither<AttendanceRecord> submit(AttendanceCapture capture,
          {String? checkOutId}) =>
      runTask(() async {
        final response = await _dio.post<Map<String, dynamic>>(
            checkOutId == null
                ? '/attendance/check-in'
                : '/attendance/$checkOutId/check-out',
            data: FormData.fromMap({
              'latitude': capture.latitude.toString(),
              'longitude': capture.longitude.toString(),
              'accuracyMeters': capture.accuracyMeters.toString(),
              'capturedAt': capture.capturedAt.toUtc().toIso8601String(),
              'photo': MultipartFile.fromBytes(capture.photo,
                  filename: 'attendance.jpg',
                  contentType: DioMediaType('image', 'jpeg')),
            }));
        return AttendanceRecord.fromJson(response.data!);
      }, operation: 'attendance.submit', category: LogCategory.network);

  FutureEither<List<AttendanceEvidence>> loadEvidence(String id) =>
      runTask(() async {
        final response = await _dio.get<List<dynamic>>(
            '/attendance/${Uri.encodeComponent(id)}/evidence');
        final result = <AttendanceEvidence>[];
        final origin = Uri.parse(_dio.options.baseUrl);
        for (final item in response.data!) {
          final json = item as Map<String, dynamic>;
          final path = Uri.parse(json['photoUrl'] as String);
          // Only send the session token to the configured API origin.
          if (path.hasAuthority ||
              path.hasScheme ||
              !path.path.startsWith('/api/attendance/')) {
            throw const FormatException('Invalid evidence photo path');
          }
          final photo = await _dio.get<List<int>>(
              origin.resolveUri(path).toString(),
              options: Options(
                  responseType: ResponseType.bytes, followRedirects: false));
          result.add(AttendanceEvidence(
              event: json['event'] as String,
              latitude: (json['latitude'] as num).toDouble(),
              longitude: (json['longitude'] as num).toDouble(),
              accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
              distanceMeters: (json['distanceMeters'] as num).toDouble(),
              capturedAt: DateTime.parse(json['capturedAt'] as String),
              submittedAt: DateTime.parse(json['submittedAt'] as String),
              photo: Uint8List.fromList(photo.data!)));
        }
        return result;
      }, operation: 'attendance.evidence', category: LogCategory.network);
}
