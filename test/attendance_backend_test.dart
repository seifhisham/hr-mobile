import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:hodour/src/data/models/attendance_model.dart';
import 'package:hodour/src/services/attendance_service.dart';
import 'package:hodour/src/services/attendance_capture_service.dart';
import 'package:hodour/src/services/auth_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('ATTENDANCE_TEST_API');
  test(
      'real REST multipart attendance validates evidence and preserves original events',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(Uri.parse(base).host, '127.0.0.1',
          reason: 'Throwaway local database only.');
      FlutterSecureStorage.setMockInitialValues({});
      final client = Dio(BaseOptions(baseUrl: base));
      final auth = AuthService(client: client)..initialize();
      addTearDown(() {
        auth.dispose();
        client.close(force: true);
      });
      expect(
          (await auth.login(
                  workspace: const String.fromEnvironment('TEST_WORKSPACE',
                      defaultValue: 'test-company'),
                  email: 'mobile-employee@example.test',
                  password: 'Isolated-employee-password-2026'))
              .isRight(),
          true);
      final service = AttendanceService(client: client);
      final initial =
          (await service.load()).getOrElse((failure) => throw failure);
      expect(initial.records, isEmpty);
      final capturedAt = DateTime.now().toUtc();
      final photo = prepareAttendancePhoto(
          image.encodeJpg(image.Image(width: 2000, height: 1000)));
      final portrait = image.Image(width: 2000, height: 1000);
      portrait.exif.imageIfd['Orientation'] = 6;
      final departurePhoto = prepareAttendancePhoto(image.encodeJpg(portrait));
      AttendanceCapture capture(
              {double? latitude,
              double? accuracy,
              DateTime? at,
              bool departure = false}) =>
          AttendanceCapture(
              latitude: latitude ?? initial.policy.latitude,
              longitude: initial.policy.longitude,
              accuracyMeters: accuracy ?? 5,
              capturedAt: at ?? capturedAt,
              photo: departure ? departurePhoto : photo);
      expect((await service.submit(capture(latitude: 0))).isLeft(), true);
      expect((await service.submit(capture(accuracy: 100))).isLeft(), true);
      expect(
          (await service.submit(capture(
                  at: DateTime.now()
                      .toUtc()
                      .subtract(const Duration(minutes: 5)))))
              .isLeft(),
          true);
      expect(
          (await service.load()).getOrElse((failure) => throw failure).records,
          isEmpty);
      final checkIn = (await service.submit(capture()))
          .getOrElse((failure) => throw failure);
      expect(checkIn.workDate, initial.workDate);
      expect(checkIn.checkOut, isNull);
      final repeated = (await service.submit(capture()))
          .getOrElse((failure) => throw failure);
      expect(repeated.id, checkIn.id);
      expect(repeated.checkIn, checkIn.checkIn);
      final checkOut = (await service.submit(capture(departure: true),
              checkOutId: checkIn.id))
          .getOrElse((failure) => throw failure);
      expect(checkOut.checkOut, isNotNull);
      final repeatedOut =
          (await service.submit(capture(), checkOutId: checkIn.id))
              .getOrElse((failure) => throw failure);
      expect(repeatedOut.checkOut, checkOut.checkOut);
      final finished =
          (await service.load()).getOrElse((failure) => throw failure);
      expect(finished.records.length, 1);
      expect(finished.canSubmit, false);
      final evidence =
          await client.get<List<dynamic>>('/attendance/${checkIn.id}/evidence');
      expect(evidence.data!.length, 2);
      for (final entry in evidence.data!.cast<Map<String, dynamic>>()) {
        expect(
            DateTime.parse(entry['capturedAt'] as String)
                .millisecondsSinceEpoch,
            capturedAt.millisecondsSinceEpoch);
        expect(entry['latitude'], initial.policy.latitude);
        expect(entry['longitude'], initial.policy.longitude);
        expect(entry['accuracyMeters'], 5);
        final event = entry['event'] as String;
        final photoResponse = await client.get<List<int>>(
            '/attendance/${checkIn.id}/photos/$event',
            options: Options(responseType: ResponseType.bytes));
        final stored =
            image.decodeJpg(Uint8List.fromList(photoResponse.data!))!;
        expect((stored.width, stored.height),
            event == 'check-in' ? (1280, 640) : (640, 1280));
        expect(stored.exif.isEmpty, true);
        expect(stored.numFrames, 1);
        expect(photoResponse.data!.length,
            lessThanOrEqualTo(initial.policy.maxPhotoBytes));
      }
    }, _RealHttpOverrides());
  },
      skip: base.isEmpty
          ? 'Requires isolated attendance backend; see README.md.'
          : false);
}
