import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as image;
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/data/repositories/attendance_repository.dart';
import 'package:hodour/src/services/attendance_service.dart';
import 'package:hodour/src/services/attendance_capture_service.dart';
import 'package:hodour/src/ui/attendance/attendance_provider.dart';
import 'package:hodour/src/utils/utils.dart';
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
  Failure? failure;
  Completer<void>? wait;
  @override
  FutureEither<AttendanceCapture?> capture(AttendancePolicy policy) async {
    calls++;
    await wait?.future;
    return failure == null ? right(value) : left(failure!);
  }
}

class FakeRepository implements AttendanceRepository {
  FakeRepository(this.responses);
  final List<Either<Failure, AttendanceSnapshot>> responses;
  int posts = 0;
  String? checkOutId;
  Completer<void>? loadWait;
  Either<Failure, AttendanceRecord> result =
      left(const NetworkFailure('Lost response'));
  @override
  FutureEither<AttendanceSnapshot> load() async {
    await loadWait?.future;
    return responses.removeAt(0);
  }

  @override
  FutureEither<AttendanceRecord> submit(AttendanceCapture capture,
      {String? checkOutId}) async {
    posts++;
    this.checkOutId = checkOutId;
    return result;
  }
}

void main() {
  test('refresh retains visible attendance through loading and failure',
      () async {
    final open = snapshot(records: [recordJson()]);
    final closed = snapshot(records: [recordJson(closed: true)]);
    final repository = FakeRepository(
        [right(open), left(const NetworkFailure('Offline')), right(closed)]);
    final capture = FakeCapture();
    final controller =
        AttendanceController(repository, capture, enabled: false);
    await controller.refresh();
    repository.loadWait = Completer<void>();
    final refresh = controller.refresh();
    expect(controller.state.snapshot, same(open));
    expect(controller.state.busy, false);
    repository.loadWait!.complete();
    await refresh;
    expect(controller.state.data, isA<RequestFailure<AttendanceSnapshot>>());
    expect(controller.state.snapshot, same(open));
    await controller.refresh();
    expect(controller.state.snapshot, same(closed));
    expect(controller.state.previousSnapshot, isNull);
    controller.dispose();
  });
  test('work progress uses elapsed check-in time across an overnight shift',
      () {
    final record = AttendanceRecord.fromJson(recordJson());
    final halfway = record.checkIn.add(const Duration(hours: 4));
    expect(record.elapsedAt(halfway), const Duration(hours: 4));
    expect(record.progressAt(halfway), 0.5);
    expect(record.progressAt(record.checkIn.subtract(const Duration(hours: 1))),
        0);
    expect(record.progressAt(record.checkIn.add(const Duration(hours: 10))), 1);
    expect(record.elapsedAt(record.checkIn.add(const Duration(hours: 10))),
        const Duration(hours: 10));
    final closed = AttendanceRecord.fromJson(recordJson(closed: true));
    expect(closed.elapsedAt(halfway.add(const Duration(days: 1))),
        const Duration(hours: 6));
  });

  test('attendance starts policy request before records finish loading',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    final recordsStarted = Completer<void>();
    final releaseRecords = Completer<void>();
    var policyStarted = false;
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      if (options.path == '/attendance/me') {
        recordsStarted.complete();
        await releaseRecords.future;
      } else if (options.path == '/attendance/policy') {
        policyStarted = true;
      }
      handler.next(options);
    }));
    dio.httpClientAdapter =
        TestAdapter((options) => options.path == '/requests/me'
            ? jsonResponse([])
            : options.path == '/attendance/policy'
                ? jsonResponse(policyJson)
                : jsonResponse({
                    'workDate': '2026-10-05',
                    'records': <Object?>[],
                    'schedule': schedules.first,
                  }));
    final loading = AttendanceService(client: dio).load();
    await recordsStarted.future;
    await Future<void>.delayed(Duration.zero);
    try {
      expect(policyStarted, isTrue,
          reason:
              'Independent requests should overlap instead of adding latency.');
    } finally {
      releaseRecords.complete();
      expect((await loading).isRight(), isTrue);
      dio.close();
    }
  });
  test('camera preparation resizes, converts to JPEG and removes EXIF', () {
    final source = image.Image(width: 1800, height: 100);
    source.exif.imageIfd['Model'] = 'private-device';
    final encoded = image.encodeJpg(source);
    expect(image.decodeJpg(encoded)!.exif.isEmpty, false);
    final prepared = prepareAttendancePhoto(encoded);
    final result = image.decodeJpg(prepared)!;
    expect(result.width, 1280);
    expect(result.height, lessThanOrEqualTo(1280));
    expect(result.exif.isEmpty, true);
    expect(() => prepareAttendancePhoto(Uint8List.fromList([1, 2])),
        throwsA(isA<CaptureFailure>()));
  });
  test('both REST uploads preserve GPS/time and send prepared JPEG bytes',
      () async {
    final photo = prepareAttendancePhoto(
        image.encodePng(image.Image(width: 1600, height: 800)));
    final at = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
    final capture = AttendanceCapture(
        latitude: 30,
        longitude: 31,
        accuracyMeters: 5,
        capturedAt: at,
        photo: photo);
    final paths = <String>[];
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
      if (options.path == '/requests/me') return jsonResponse([]);
      paths.add(options.uri.path);
      expect(options.contentType, startsWith('multipart/form-data; boundary='));
      final form = options.data as FormData;
      expect(form.fields.map((f) => f.key).toSet(),
          {'latitude', 'longitude', 'accuracyMeters', 'capturedAt'});
      expect(Map.fromEntries(form.fields), {
        'latitude': '30.0',
        'longitude': '31.0',
        'accuracyMeters': '5.0',
        'capturedAt': at.toIso8601String(),
      });
      expect(form.files.single.key, 'photo');
      expect(form.files.single.value.contentType.toString(), 'image/jpeg');
      return jsonResponse(recordJson(closed: true));
    });
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      if (options.method == 'POST') {
        final form = (options.data as FormData).clone();
        final uploaded = await form.files.single.value
            .finalize()
            .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
        expect(uploaded, photo);
        final decoded = image.decodeJpg(Uint8List.fromList(uploaded))!;
        expect((decoded.width, decoded.height), (1280, 640));
      }
      handler.next(options);
    }));
    final service = AttendanceService(client: dio);
    expect((await service.load()).isRight(), true);
    expect((await service.submit(capture)).isRight(), true);
    expect(
        (await service.submit(capture, checkOutId: 'owned-record')).isRight(),
        true);
    expect(paths,
        ['/api/attendance/check-in', '/api/attendance/owned-record/check-out']);
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
  test('manual checkout racing automatic checkout reconciles 409 without retry',
      () async {
    final open = snapshot(records: [recordJson()]);
    final closed = snapshot(records: [recordJson(closed: true)]);
    final repository = FakeRepository([right(open), right(open), right(closed)])
      ..result = left(const ServerFailure('Already closed', statusCode: 409));
    final controller =
        AttendanceController(repository, FakeCapture(), enabled: false);
    await controller.refresh();
    await controller.submit();
    expect(repository.posts, 1);
    expect(controller.state.snapshot!.current!.checkOut, isNotNull);
    expect(controller.state.snapshot!.canSubmit, false);
    expect(controller.state.action, isA<RequestFailure<void>>());
    expect((controller.state.action as RequestFailure<void>).failure.message,
        'Already closed');
    expect(controller.state.pending, isNull);
    controller.dispose();
  });
  test('confirmed writes expose open/closed interval even when read-back fails',
      () async {
    for (final checkOut in [false, true]) {
      final before = snapshot(records: checkOut ? [recordJson()] : []);
      final saved = AttendanceRecord.fromJson(recordJson(closed: checkOut));
      final repository = FakeRepository([
        right(before),
        right(before),
        left(const NetworkFailure('Read-back unavailable'))
      ])
        ..result = right(saved);
      final controller =
          AttendanceController(repository, FakeCapture(), enabled: false);
      await controller.refresh();
      final observed = <AttendanceSnapshot>[];
      final remove = controller.addListener((value) {
        if (value.data case RequestSuccess<AttendanceSnapshot>(:final data)) {
          observed.add(data);
        }
      }, fireImmediately: false);
      await controller.submit();
      expect(observed.last.current, saved);
      expect(controller.state.snapshot!.current, saved);
      expect(controller.state.snapshot!.open != null, !checkOut);
      expect(controller.state.pending, isNotNull);
      remove();
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
