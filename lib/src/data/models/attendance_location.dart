import 'package:equatable/equatable.dart';

class AttendanceTrackingPolicy extends Equatable {
  const AttendanceTrackingPolicy(
      {required this.radiusMeters,
      required this.graceSeconds,
      required this.updateIntervalSeconds,
      required this.staleAfterSeconds,
      required this.maxCaptureAgeSeconds,
      required this.maxAccuracyMeters,
      required this.confirmationSeconds});
  final double radiusMeters, maxAccuracyMeters;
  final int graceSeconds,
      updateIntervalSeconds,
      staleAfterSeconds,
      maxCaptureAgeSeconds,
      confirmationSeconds;
  factory AttendanceTrackingPolicy.fromJson(Map<String, dynamic> json) {
    final policy = AttendanceTrackingPolicy(
        radiusMeters: (json['radiusMeters'] as num).toDouble(),
        graceSeconds: json['graceSeconds'] as int,
        updateIntervalSeconds: json['updateIntervalSeconds'] as int,
        staleAfterSeconds: json['staleAfterSeconds'] as int,
        maxCaptureAgeSeconds: json['maxCaptureAgeSeconds'] as int,
        maxAccuracyMeters: (json['maxAccuracyMeters'] as num).toDouble(),
        confirmationSeconds: json['confirmationSeconds'] as int);
    if (policy.props.any((value) => !(value as num).isFinite || value <= 0)) {
      throw const FormatException('Invalid attendance tracking policy');
    }
    return policy;
  }
  @override
  List<Object> get props => [
        radiusMeters,
        graceSeconds,
        updateIntervalSeconds,
        staleAfterSeconds,
        maxCaptureAgeSeconds,
        maxAccuracyMeters,
        confirmationSeconds
      ];
}

class AttendanceLocation extends Equatable {
  const AttendanceLocation(
      {required this.status,
      this.lastCapturedAt,
      this.outsideSince,
      this.returnBy,
      this.distanceMeters,
      this.accuracyMeters,
      this.autoCheckedOutAt});
  final String status;
  final DateTime? lastCapturedAt, outsideSince, returnBy, autoCheckedOutAt;
  final double? distanceMeters, accuracyMeters;
  factory AttendanceLocation.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    final status = json['status'] as String;
    if (!['inside', 'outside', 'unavailable', 'auto-checked-out']
        .contains(status)) {
      throw const FormatException('Invalid attendance location status');
    }
    return AttendanceLocation(
        status: status,
        lastCapturedAt: date('lastCapturedAt'),
        outsideSince: date('outsideSince'),
        returnBy: date('returnBy'),
        autoCheckedOutAt: date('autoCheckedOutAt'),
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble());
  }
  @override
  List<Object?> get props => [
        status,
        lastCapturedAt,
        outsideSince,
        returnBy,
        distanceMeters,
        accuracyMeters,
        autoCheckedOutAt
      ];
}

class AttendanceLocationFix {
  const AttendanceLocationFix(
      {required this.latitude,
      required this.longitude,
      required this.accuracyMeters,
      required this.capturedAt});
  final double latitude, longitude, accuracyMeters;
  final DateTime capturedAt;
  bool isFresh(
          DateTime now, AttendanceTrackingPolicy policy, DateTime? previous) =>
      latitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.isFinite &&
      longitude.abs() <= 180 &&
      accuracyMeters.isFinite &&
      accuracyMeters > 0 &&
      !capturedAt.isAfter(now) &&
      now.difference(capturedAt) <=
          Duration(seconds: policy.maxCaptureAgeSeconds) &&
      (previous == null || capturedAt.isAfter(previous));
  Map<String, Object> toJson() => {
        'available': true,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'capturedAt': capturedAt.toUtc().toIso8601String()
      };
}
