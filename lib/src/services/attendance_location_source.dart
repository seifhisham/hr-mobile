import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:easy_localization/easy_localization.dart';
import '../data/models/attendance_location.dart';
import '../utils/utils.dart';

class AttendanceLocationSource {
  static final instance = AttendanceLocationSource();
  static bool get supported =>
      !kIsWeb &&
      [TargetPlatform.android, TargetPlatform.iOS]
          .contains(defaultTargetPlatform);

  Future<void> checkAccess() async {
    if (!supported) throw const CaptureFailure('tracking.phone_only');
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CaptureFailure('attendance.location_off',
          recovery: CaptureRecovery.locationSettings);
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const CaptureFailure('attendance.location_blocked',
          recovery: CaptureRecovery.appSettings);
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw const CaptureFailure('attendance.location_denied');
    }
  }

  // Called only by the explained, on-duty UI action. Never from a background timer.
  Future<void> requestAccess() async {
    if (!supported) return;
    await permissions.Permission.locationWhenInUse.request();
    if (await permissions.Permission.locationWhenInUse.isGranted) {
      await permissions.Permission.locationAlways.request();
    }
  }

  Future<bool> hasBackgroundAccess() async =>
      supported &&
      await Geolocator.checkPermission() == LocationPermission.always;

  Stream<AttendanceLocationFix> positions(AttendanceTrackingPolicy policy) {
    final LocationSettings settings = defaultTargetPlatform ==
            TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: Duration(seconds: policy.updateIntervalSeconds),
            foregroundNotificationConfig: ForegroundNotificationConfig(
                notificationTitle: 'tracking.title'.tr(),
                notificationText: 'tracking.background_notice'.tr(),
                notificationIcon: const AndroidResource(name: 'ic_attendance'),
                enableWakeLock: true,
                setOngoing: true))
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true);
    return Geolocator.getPositionStream(locationSettings: settings).map(_fix);
  }

  Future<AttendanceLocationFix> capture() async {
    await checkAccess();
    return _fix(await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20))));
  }

  AttendanceLocationFix _fix(Position position) => AttendanceLocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      capturedAt: position.timestamp.toUtc());
}
