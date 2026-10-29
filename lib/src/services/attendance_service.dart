import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../data/models/attendance_model.dart';
import '../data/models/attendance_location.dart';
import 'auth_service.dart';
import 'requests_service.dart';
import '../data/repositories/attendance_repository.dart';
import '../utils/utils.dart';

class AttendanceService implements AttendanceRepository {
  AttendanceService({Dio? client}) : _client = client;
  static final instance = AttendanceService();
  final Dio? _client;
  Dio get _dio => _client ?? AppConfig.dio;
  FutureEither<AttendanceLocation> reportLocation(
          String id, AttendanceLocationFix? fix,
          {CancelToken? cancelToken}) =>
      runTask(() async {
        final response = await _dio.post<Map<String, dynamic>>(
            '/attendance/${Uri.encodeComponent(id)}/location',
            data: fix?.toJson() ?? {'available': false},
            options: Options(extra: {
              if (_client == null)
                'expectedSessionRevision': AuthService.instance.sessionRevision,
            }),
            cancelToken: cancelToken);
        return AttendanceLocation.fromJson(response.data!);
      }, operation: 'attendance.location', category: LogCategory.network);
  @override
  FutureEither<AttendanceSnapshot> load() => runTask(() async {
        final responses = await Future.wait([
          _dio.get<Map<String, dynamic>>('/attendance/me'),
          _dio.get<Map<String, dynamic>>('/attendance/policy'),
        ]);
        // /requests/me guarantees ownership; exhaust pagination before eligibility.
        final requests = await RequestsService(client: _dio).load();
        return AttendanceSnapshot.fromJson(
            responses[0].data!, AttendancePolicy.fromJson(responses[1].data!),
            requests:
                requests.fold((failure) => throw failure, (items) => items));
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
              path.hasQuery ||
              path.hasFragment ||
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
