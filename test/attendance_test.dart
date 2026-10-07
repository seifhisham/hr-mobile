import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as image;
import 'package:hrmobile/src/data/models/attendance_model.dart';
import 'package:hrmobile/src/data/repositories/attendance_repository.dart';
import 'package:hrmobile/src/services/attendance_service.dart';
import 'package:hrmobile/src/services/attendance_capture_service.dart';
import 'package:hrmobile/src/ui/attendance/attendance_provider.dart';
import 'package:hrmobile/src/utils/utils.dart';
import 'auth_session_test.dart' show TestAdapter, jsonResponse, schedules;

final policyJson = {
  'latitude': 30.0,
  'longitude': 31.0,
  'radiusMeters': 50,
  'maxAccuracyMeters': 50,
  'maxCaptureAgeSeconds': 120,
  'maxPhotoBytes': 5242880,
  'photoFormats': ['jpeg', 'png']
};
Map<String, dynamic> recordJson(
        {String date = '2026-10-05', bool closed = false}) =>
    {
      'id': 'owned-record',
      'workDate': date,
      'checkIn': '2026-10-05T22:00:00Z',
      'checkOut': closed ? '2026-10-06T04:00:00Z' : null,
      'timezone': 'Africa/Cairo',
      'schedule': schedules.first,
      'status': 'On time'
    };
AttendanceSnapshot snapshot({List<Map<String, dynamic>> records = const []}) =>
    AttendanceSnapshot.fromJson({
      'workDate': '2026-10-05',
      'records': records,
      'schedule': schedules.first
    }, AttendancePolicy.fromJson(policyJson));
AttendanceCapture evidence({DateTime? at}) => AttendanceCapture(
    latitude: 30,
    longitude: 31,
    accuracyMeters: 5,
    capturedAt: at ?? DateTime.now().toUtc(),
    photo: Uint8List.fromList([1, 2, 3]));

class FakeCapture extends AttendanceCaptureService {
  int calls = 0;
  AttendanceCapture? value = evidence();
  Completer<void>? wait;
  @override
  FutureEither<AttendanceCapture?> capture(AttendancePolicy policy) async {
    calls++;
    await wait?.future;
    return right(value);
  }
}

class FakeRepository implements AttendanceRepository {
  FakeRepository(this.responses);
  final List<Either<Failure, AttendanceSnapshot>> responses;
  int posts = 0;
  String? checkOutId;
  Either<Failure, AttendanceRecord> result =
      left(const NetworkFailure('Lost response'));
  @override
  FutureEither<AttendanceSnapshot> load() async => responses.removeAt(0);
  @override
  FutureEither<AttendanceRecord> submit(AttendanceCapture capture,
      {String? checkOutId}) async {
    posts++;
    this.checkOutId = checkOutId;
    return result;
  }
}

void main() {
  test('camera preparation resizes, converts to JPEG and removes EXIF', () {
    final source = image.Image(width: 1800, height: 100);
    source.exif.imageIfd['Model'] = 'private-device';
    final encoded = image.encodeJpg(source);
    expect(image.decodeJpg(encoded)!.exif.isEmpty, false);
    final prepared = prepareAttendancePhoto(encoded);
    final result = image.decodeJpg(prepared)!;
    expect(result.width, 1600);
    expect(result.height, lessThanOrEqualTo(1600));
    expect(result.exif.isEmpty, true);
    expect(() => prepareAttendancePhoto(Uint8List.fromList([1, 2])),
        throwsA(isA<CaptureFailure>()));
  });
  test('REST multipart uses exact fields and owned check-out ID', () async {
    final dio = Dio(BaseOptions(
        baseUrl: 'https://example.test/api',
        headers: {'Content-Type': 'application/json'}));
    dio.httpClientAdapter = TestAdapter((options) {
      if (options.path == '/attendance/me') {
        return jsonResponse({
          'workDate': '2026-10-05',
          'records': <Object?>[],
          'schedule': schedules.first
        });
      }
      if (options.path == '/attendance/policy') return jsonResponse(policyJson);
      expect(options.uri.path, '/api/attendance/owned-record/check-out');
      expect(options.contentType, startsWith('multipart/form-data; boundary='));
      final form = options.data as FormData;
      expect(form.fields.map((f) => f.key).toSet(),
          {'latitude', 'longitude', 'accuracyMeters', 'capturedAt'});
      expect(form.fields.firstWhere((f) => f.key == 'capturedAt').value,
          endsWith('Z'));
      expect(form.files.single.key, 'photo');
      expect(form.files.single.value.contentType.toString(), 'image/jpeg');
      return jsonResponse(recordJson(closed: true));
    });
    final service = AttendanceService(client: dio);
    expect((await service.load()).isRight(), true);
    expect(
        (await service.submit(evidence(), checkOutId: 'owned-record'))
            .isRight(),
        true);
    dio.close();
  });
  test('server workday governs actions; closed and previous open block capture',
      () async {
    for (final records in [
      [recordJson(closed: true)],
      [recordJson(date: '2026-10-04')]
    ]) {
      final data = snapshot(records: records);
      final repository = FakeRepository([right(data), right(data)]);
      final capture = FakeCapture();
      final controller =
          AttendanceController(repository, capture, enabled: false);
      await controller.refresh();
      await controller.submit();
      expect(capture.calls, 0);
      expect(repository.posts, 0);
      expect(controller.state.snapshot!.workDate, '2026-10-05');
      controller.dispose();
    }
  });
  test(
      'lost check-in response reconciles recorded workday without another POST',
      () async {
    final repository = FakeRepository([
      right(snapshot()),
      right(snapshot()),
      right(snapshot(records: [recordJson()]))
    ]);
    final controller =
        AttendanceController(repository, FakeCapture(), enabled: false);
    await controller.refresh();
    await controller.submit();
    expect(controller.state.noticeKey, 'attendance.confirmed');
    expect(repository.posts, 1);
    expect(controller.state.pending, isNull);
    controller.dispose();
  });
  test(
      'unknown checkout outcome blocks retry until reconciliation and retains ID',
      () async {
    final open = snapshot(records: [recordJson()]);
    final repository = FakeRepository([
      right(open),
      right(open),
      left(const NetworkFailure('Offline')),
      right(snapshot(records: [recordJson(closed: true)]))
    ]);
    final controller =
        AttendanceController(repository, FakeCapture(), enabled: false);
    await controller.refresh();
    await controller.submit();
    expect(repository.checkOutId, 'owned-record');
    expect(controller.state.pending!.checkOutId, 'owned-record');
    await controller.submit();
    expect(repository.posts, 1);
    await controller.refresh();
    expect(controller.state.noticeKey, 'attendance.confirmed');
    expect(controller.state.pending, isNull);
    controller.dispose();
  });
  test('expired evidence and cancellation never submit', () async {
    for (final capture in [
      FakeCapture()
        ..value =
            evidence(at: DateTime.now().subtract(const Duration(minutes: 3))),
      FakeCapture()..value = null
    ]) {
      final repository = FakeRepository([right(snapshot()), right(snapshot())]);
      final controller =
          AttendanceController(repository, capture, enabled: false);
      await controller.refresh();
      await controller.submit();
      expect(repository.posts, 0);
      controller.dispose();
    }
  });
  test('duplicate taps and disposed session cannot submit after capture',
      () async {
    final repository = FakeRepository([right(snapshot()), right(snapshot())]);
    final capture = FakeCapture()..wait = Completer<void>();
    final controller =
        AttendanceController(repository, capture, enabled: false);
    await controller.refresh();
    final action = controller.submit();
    await Future<void>.delayed(Duration.zero);
    await controller.submit();
    expect(capture.calls, 1);
    controller.dispose();
    capture.wait!.complete();
    await action;
    expect(repository.posts, 0);
  });
}
