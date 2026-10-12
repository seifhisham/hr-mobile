import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import '../data/models/attendance_model.dart';
import '../utils/utils.dart';
import '../shared/helpers/delete_attendance_photo.dart';
import '../shared/helpers/show_attendance_camera.dart';

class AttendanceCaptureService {
  AttendanceCaptureService(
      {ImagePicker? picker, Future<XFile?> Function()? takePhoto})
      : _picker = picker ?? ImagePicker(),
        _takePhoto = takePhoto ?? showAttendanceCamera;
  static final instance = AttendanceCaptureService();
  final ImagePicker _picker;
  final Future<XFile?> Function() _takePhoto;

  FutureEither<AttendanceCapture?> capture(AttendancePolicy policy) =>
      runTask(() async {
        if (kIsWeb ||
            (defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS)) {
          throw const CaptureFailure('attendance.phone_only');
        }
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw const CaptureFailure('attendance.location_off',
              recovery: CaptureRecovery.locationSettings);
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          throw const CaptureFailure('attendance.location_blocked',
              recovery: CaptureRecovery.appSettings);
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.unableToDetermine) {
          throw const CaptureFailure('attendance.location_denied');
        }
        final capturedAt = DateTime.now().toUtc();
        XFile? photo;
        try {
          photo = await _takePhoto();
          if (photo == null) return null;
          final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 25)));
          final now = DateTime.now().toUtc();
          if (now.difference(capturedAt).inSeconds >
                  policy.maxCaptureAgeSeconds ||
              now.difference(position.timestamp.toUtc()).inSeconds >
                  policy.maxCaptureAgeSeconds) {
            throw const CaptureFailure('attendance.capture_expired');
          }
          if (!position.accuracy.isFinite ||
              position.accuracy <= 0 ||
              position.accuracy > policy.maxAccuracyMeters) {
            throw const CaptureFailure('attendance.accuracy_low');
          }
          if (Geolocator.distanceBetween(position.latitude, position.longitude,
                  policy.latitude, policy.longitude) >
              policy.radiusMeters) {
            throw const CaptureFailure('attendance.outside_office');
          }
          if (!policy.photoFormats.contains('jpeg')) {
            throw const CaptureFailure('attendance.photo_invalid');
          }
          final Uint8List bytes;
          try {
            bytes = await compute(
                prepareAttendancePhoto, await photo.readAsBytes());
          } on CaptureFailure {
            rethrow;
          } catch (_) {
            throw const CaptureFailure('attendance.photo_compression_failed');
          }
          if (bytes.length > policy.maxPhotoBytes) {
            throw const CaptureFailure('attendance.photo_large');
          }
          return AttendanceCapture(
              latitude: position.latitude,
              longitude: position.longitude,
              accuracyMeters: position.accuracy,
              capturedAt: capturedAt,
              photo: bytes);
        } on TimeoutException {
          throw const CaptureFailure('attendance.location_timeout');
        } on LocationServiceDisabledException {
          throw const CaptureFailure('attendance.location_off',
              recovery: CaptureRecovery.locationSettings);
        } on PlatformException catch (error) {
          if (error.code.toLowerCase().contains('access_denied')) {
            throw const CaptureFailure('attendance.camera_denied',
                recovery: CaptureRecovery.appSettings);
          }
          throw const CaptureFailure('attendance.capture_failed');
        } finally {
          if (photo != null) await deleteAttendancePhoto(photo);
        }
      }, operation: 'attendance.capture');

  /// Discard interrupted camera results: evidence must always be fresh.
  Future<void> discardLostCapture() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final lost = await _picker.retrieveLostData();
      for (final photo in lost.files ?? <XFile>[]) {
        await deleteAttendancePhoto(photo);
      }
    } catch (error) {
      AppLogger.warning('Unable to discard interrupted camera capture',
          context: {'type': error.runtimeType.toString()});
    }
  }

  Future<bool> openSettings(CaptureRecovery recovery) =>
      recovery == CaptureRecovery.locationSettings
          ? Geolocator.openLocationSettings()
          : Geolocator.openAppSettings();
}

Uint8List prepareAttendancePhoto(Uint8List bytes) {
  final image.Image? decoded;
  try {
    decoded = image.decodeImage(bytes);
  } catch (_) {
    throw const CaptureFailure('attendance.photo_invalid');
  }
  if (decoded == null || decoded.numFrames != 1) {
    throw const CaptureFailure('attendance.photo_invalid');
  }
  try {
    final oriented = image.bakeOrientation(decoded);
    final resized = oriented.width > 1280 || oriented.height > 1280
        ? image.copyResize(oriented,
            width: oriented.width >= oriented.height ? 1280 : null,
            height: oriented.height > oriented.width ? 1280 : null)
        : oriented;
    resized.exif = image.ExifData();
    resized.iccProfile = null;
    resized.textData = null;
    return image.encodeJpg(resized, quality: 85);
  } catch (_) {
    throw const CaptureFailure('attendance.photo_compression_failed');
  }
}
