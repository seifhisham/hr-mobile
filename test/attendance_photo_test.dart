import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/services/attendance_capture_service.dart';
import 'package:hodour/src/ui/attendance/attendance_provider.dart';
import 'package:hodour/src/utils/utils.dart';
import 'attendance_test.dart'
    show policyJson, snapshot, recordJson, FakeRepository;

class _Camera extends ImagePicker {
  XFile? photo;
  Completer<void>? wait;
  DateTime? returnedAt;
  List<XFile> lost = [];
  @override
  Future<XFile?> pickImage(
      {required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      CameraDevice preferredCameraDevice = CameraDevice.rear,
      bool requestFullMetadata = true}) async {
    expect(source, ImageSource.camera);
    expect(requestFullMetadata, false);
    // One in-memory encode; the picker must not create another resized copy.
    expect(maxWidth, isNull);
    expect(maxHeight, isNull);
    expect(imageQuality, isNull);
    await wait?.future;
    returnedAt = DateTime.now().toUtc();
    return photo;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async =>
      LostDataResponse(files: lost);
}

class _Location extends GeolocatorPlatform {
  final position = Position(
      longitude: 31,
      latitude: 30,
      timestamp: DateTime.now().toUtc(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0);
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      position;
}

class _UnreadablePhoto extends XFile {
  _UnreadablePhoto(super.path);
  @override
  Future<Uint8List> readAsBytes() async =>
      throw const FileSystemException('Test read failure');
}

class _SlowPhoto extends XFile {
  _SlowPhoto(super.path);
  @override
  Future<Uint8List> readAsBytes() async {
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    return super.readAsBytes();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    (2000, 1000, 1280, 640),
    (1000, 2000, 640, 1280),
    (640, 480, 640, 480),
    (480, 640, 480, 640)
  ]) {
    test('JPEG preparation preserves proportions without enlargement: $size',
        () {
      final source = image.Image(width: size.$1, height: size.$2);
      final output = prepareAttendancePhoto(image.encodePng(source));
      expect(output.take(2), [0xff, 0xd8]);
      final decoded = image.decodeJpg(output)!;
      expect((decoded.width, decoded.height), (size.$3, size.$4));
      expect(decoded.numFrames, 1);
      expect(decoded.exif.isEmpty, true);
      if (size.$1 < 1280 && size.$2 < 1280) {
        expect(output, image.encodeJpg(source, quality: 85));
      }
    });
  }
  for (var orientation = 1; orientation <= 8; orientation++) {
    test('orientation $orientation is baked before EXIF is stripped', () {
      final source = image.Image(width: 80, height: 40);
      image.fill(source, color: image.ColorRgb8(0, 0, 255));
      image.fillRect(source,
          x1: 0, y1: 0, x2: 39, y2: 19, color: image.ColorRgb8(255, 0, 0));
      source.exif.imageIfd['Orientation'] = orientation;
      source.exif.imageIfd['Model'] = 'private-device';
      final output =
          image.decodeJpg(prepareAttendancePhoto(image.encodeJpg(source)))!;
      expect(
          (output.width, output.height), orientation < 5 ? (80, 40) : (40, 80));
      final right = [2, 3, 6, 7].contains(orientation);
      final bottom = [3, 4, 7, 8].contains(orientation);
      final red = output.getPixel(
          right ? output.width - 10 : 10, bottom ? output.height - 10 : 10);
      expect(red.r, greaterThan(200));
      expect(red.b, lessThan(50));
      expect(output.exif.isEmpty, true);
    });
  }
  test('invalid and animated images are rejected', () {
    final animated = image.Image(width: 8, height: 8)..addFrame();
    for (final bytes in [
      Uint8List.fromList([1, 2]),
      image.encodeGif(animated)
    ]) {
      expect(
          () => prepareAttendancePhoto(bytes), throwsA(isA<CaptureFailure>()));
    }
  });

  group('camera preparation and cleanup', () {
    late Directory directory;
    late _Camera camera;
    late _Location location;
    late GeolocatorPlatform originalLocation;
    late AttendanceCaptureService service;
    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      originalLocation = GeolocatorPlatform.instance;
      location = _Location();
      GeolocatorPlatform.instance = location;
      directory =
          await Directory.systemTemp.createTemp('attendance-photo-test-');
      camera = _Camera();
      service = AttendanceCaptureService(
          picker: camera,
          takePhoto: () => camera.pickImage(
              source: ImageSource.camera, requestFullMetadata: false));
    });
    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      GeolocatorPlatform.instance = originalLocation;
      await directory.delete(recursive: true);
    });
    Future<File> writePhoto() => File('${directory.path}/camera.jpg')
        .writeAsBytes(image.encodeJpg(image.Image(width: 1600, height: 800)));

    test('success retains evidence time/GPS and leaves no compressed file',
        () async {
      final file = await writePhoto();
      camera.photo = XFile(file.path);
      final before = DateTime.now().toUtc();
      final capture =
          (await service.capture(AttendancePolicy.fromJson(policyJson)))
              .getOrElse((failure) => throw failure)!;
      expect(capture.capturedAt.isBefore(before), false);
      expect(capture.capturedAt.isAfter(camera.returnedAt!), false);
      expect(capture.latitude, location.position.latitude);
      expect(capture.longitude, location.position.longitude);
      expect(capture.accuracyMeters, location.position.accuracy);
      expect(image.decodeJpg(capture.photo)!.width, 1280);
      expect(await directory.list().toList(), isEmpty);
    });
    test('read failure is recoverable and deletes the original', () async {
      final file = await writePhoto();
      camera.photo = _UnreadablePhoto(file.path);
      final result =
          await service.capture(AttendancePolicy.fromJson(policyJson));
      result.fold((failure) {
        expect(failure, isA<CaptureFailure>());
        expect(failure.message, 'attendance.photo_compression_failed');
        expect((failure as CaptureFailure).recovery, CaptureRecovery.retry);
      }, (_) => fail('Must not return successful evidence'));
      expect(await directory.list().toList(), isEmpty);
    });
    test('corrupt capture is deleted and cannot trigger either attendance POST',
        () async {
      for (final records in [
        <Map<String, dynamic>>[],
        [recordJson()]
      ]) {
        final file =
            await File('${directory.path}/camera.jpg').writeAsBytes([1, 2]);
        camera.photo = XFile(file.path);
        final data = snapshot(records: records);
        final repository = FakeRepository([right(data), right(data)]);
        final controller =
            AttendanceController(repository, service, enabled: false);
        await controller.refresh();
        await controller.submit();
        expect(repository.posts, 0);
        expect(controller.state.action, isA<RequestFailure<void>>());
        expect(controller.state.pending, isNull);
        expect(await directory.list().toList(), isEmpty);
        controller.dispose();
      }
    });
    test('cancellation and lost camera results leave no temporary files',
        () async {
      final result =
          await service.capture(AttendancePolicy.fromJson(policyJson));
      expect(result.getOrElse((failure) => throw failure), isNull);
      final lost = await writePhoto();
      camera.lost = [XFile(lost.path)];
      await service.discardLostCapture();
      expect(await directory.list().toList(), isEmpty);
    });
    test(
        'abandoning a pending camera flow deletes its returned capture without POST',
        () async {
      final file = await writePhoto();
      camera.photo = XFile(file.path);
      camera.wait = Completer<void>();
      final repository = FakeRepository([right(snapshot()), right(snapshot())]);
      final controller =
          AttendanceController(repository, service, enabled: false);
      await controller.refresh();
      final submitting = controller.submit();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      camera.wait!.complete();
      await submitting;
      expect(repository.posts, 0);
      expect(await directory.list().toList(), isEmpty);
    });
    test('time spent preparing a photo cannot freshen stale evidence',
        () async {
      final file = await writePhoto();
      camera.photo = _SlowPhoto(file.path);
      final policy =
          AttendancePolicy.fromJson({...policyJson, 'maxCaptureAgeSeconds': 1});
      final data = AttendanceSnapshot(
          workDate: '2026-10-05',
          records: const [],
          schedule: snapshot().schedule,
          policy: policy);
      final repository = FakeRepository([right(data), right(data)]);
      final controller =
          AttendanceController(repository, service, enabled: false);
      await controller.refresh();
      await controller.submit();
      expect(repository.posts, 0);
      final failure = controller.state.action as RequestFailure<void>;
      expect(failure.failure.message, 'attendance.capture_expired');
      expect(await directory.list().toList(), isEmpty);
      controller.dispose();
    });
  });
}
