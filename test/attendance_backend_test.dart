import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:hrmobile/src/data/models/attendance_model.dart';
import 'package:hrmobile/src/services/attendance_service.dart';
import 'package:hrmobile/src/services/auth_service.dart';

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
                  email: 'mobile-employee@example.test',
                  password: 'Isolated-employee-password-2026'))
              .isRight(),
          true);
      final service = AttendanceService(client: client);
      final initial =
          (await service.load()).getOrElse((failure) => throw failure);
      expect(initial.records, isEmpty);
      final photo = image.encodeJpg(image.Image(width: 10, height: 10));
      AttendanceCapture capture(
              {double? latitude, double? accuracy, DateTime? at}) =>
          AttendanceCapture(
              latitude: latitude ?? initial.policy.latitude,
              longitude: initial.policy.longitude,
              accuracyMeters: accuracy ?? 5,
              capturedAt: at ?? DateTime.now().toUtc(),
              photo: photo);
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
      final checkOut = (await service.submit(capture(), checkOutId: checkIn.id))
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
      final photoResponse = await client.get<List<int>>(
          '/attendance/${checkIn.id}/photos/check-in',
          options: Options(responseType: ResponseType.bytes));
      expect(photoResponse.data, isNotEmpty);
    }, _RealHttpOverrides());
  },
      skip: base.isEmpty
          ? 'Requires isolated attendance backend; see README.md.'
          : false);
}
