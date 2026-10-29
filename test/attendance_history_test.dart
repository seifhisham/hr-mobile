import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/services/attendance_service.dart';
import 'auth_session_test.dart' show TestAdapter, jsonResponse;
import 'attendance_test.dart' show recordJson;

void main() {
  test('workday filters are inclusive and combine with status', () {
    final records = [
      AttendanceRecord.fromJson(recordJson(date: '2026-10-04')),
      AttendanceRecord.fromJson(
          {...recordJson(date: '2026-10-05'), 'status': 'Late'}),
      AttendanceRecord.fromJson(recordJson(date: '2026-10-06')),
    ];
    expect(
        filterAttendance(records, from: '2026-10-05', to: '2026-10-06').length,
        2);
    expect(
        filterAttendance(records,
                from: '2026-10-05', to: '2026-10-05', status: 'Late')
            .single
            .workDate,
        '2026-10-05');
    expect(filterAttendance(records, status: 'Missing check-out'), isEmpty);
    expect(filterAttendance(records).length, 3);
  });
  test('private evidence uses bearer client and origin without double api',
      () async {
    final client = Dio(BaseOptions(
        baseUrl: 'https://example.test/api',
        headers: {'Authorization': 'Bearer test-token'}));
    var photos = 0;
    client.httpClientAdapter = TestAdapter((request) {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.path.endsWith('/evidence')) {
        return jsonResponse([
          {
            'event': 'check-in',
            'latitude': 30,
            'longitude': 31,
            'accuracyMeters': 5,
            'distanceMeters': 10,
            'capturedAt': '2026-10-05T10:00:00Z',
            'submittedAt': '2026-10-05T10:00:01Z',
            'photoUrl': '/api/attendance/owned/photos/check-in'
          }
        ]);
      }
      expect(request.uri.toString(),
          'https://example.test/api/attendance/owned/photos/check-in');
      expect(request.followRedirects, isFalse);
      photos++;
      return ResponseBody.fromBytes([1, 2, 3], 200,
          headers: {
            'content-type': ['image/jpeg']
          });
    });
    final result =
        await AttendanceService(client: client).loadEvidence('owned');
    result.fold((failure) => fail(failure.message), (items) {
      expect(items.single.photo, [1, 2, 3]);
      expect(items.single.accuracyMeters, 5);
    });
    expect(photos, 1);
  });
  test('empty evidence succeeds and foreign photo URLs are rejected', () async {
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    var foreign = false;
    client.httpClientAdapter = TestAdapter((request) => jsonResponse(foreign
        ? [
            {'photoUrl': 'https://other.test/photo'}
          ]
        : []));
    final service = AttendanceService(client: client);
    (await service.loadEvidence('owned')).fold(
        (failure) => fail(failure.message), (items) => expect(items, isEmpty));
    foreign = true;
    expect((await service.loadEvidence('owned')).isLeft(), isTrue);
  });
}
