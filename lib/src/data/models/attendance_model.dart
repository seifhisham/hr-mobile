import 'package:equatable/equatable.dart';
import 'dart:typed_data';
import 'user_model.dart';
import 'employee_request.dart';
import 'attendance_location.dart';

class AttendancePolicy extends Equatable {
  @override
  List<Object?> get props => [
        branchId,
        branchName,
        latitude,
        longitude,
        radiusMeters,
        maxAccuracyMeters,
        maxCaptureAgeSeconds,
        maxPhotoBytes,
        photoFormats,
        tracking
      ];

  const AttendancePolicy(
      {required this.latitude,
      required this.longitude,
      required this.radiusMeters,
      required this.maxAccuracyMeters,
      required this.maxCaptureAgeSeconds,
      required this.maxPhotoBytes,
      required this.photoFormats,
      this.tracking,
      this.branchId,
      this.branchName});
  final String? branchId, branchName;
  final AttendanceTrackingPolicy? tracking;
  final double latitude, longitude, radiusMeters, maxAccuracyMeters;
  final int maxCaptureAgeSeconds, maxPhotoBytes;
  final List<String> photoFormats;
  factory AttendancePolicy.fromJson(Map<String, dynamic> json) =>
      AttendancePolicy(
          branchId: json['branchId'] as String?,
          branchName: json['branchName'] as String?,
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
          radiusMeters: (json['radiusMeters'] as num).toDouble(),
          maxAccuracyMeters: (json['maxAccuracyMeters'] as num).toDouble(),
          maxCaptureAgeSeconds: json['maxCaptureAgeSeconds'] as int,
          maxPhotoBytes: json['maxPhotoBytes'] as int,
          photoFormats: (json['photoFormats'] as List).cast<String>(),
          tracking: json['tracking'] == null
              ? null
              : AttendanceTrackingPolicy.fromJson(
                  json['tracking'] as Map<String, dynamic>));
}

class AttendanceRecord extends Equatable {
  @override
  List<Object?> get props => [
        id,
        branchId,
        branchName,
        workDate,
        timezone,
        checkIn,
        checkOut,
        schedule,
        status,
        location
      ];

  const AttendanceRecord(
      {required this.id,
      required this.workDate,
      required this.checkIn,
      required this.checkOut,
      required this.timezone,
      required this.schedule,
      this.branchId,
      this.branchName,
      this.status,
      this.location});
  final String? branchId, branchName;
  final AttendanceLocation? location;
  final String id, workDate, timezone;
  final DateTime checkIn;
  final DateTime? checkOut;
  final WorkSchedule schedule;
  final String? status;
  Duration elapsedAt(DateTime now) {
    final elapsed = (checkOut ?? now).difference(checkIn);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  double progressAt(DateTime now) {
    int minutes(String time) {
      final parts = time.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final shiftMinutes =
        (minutes(schedule.end) - minutes(schedule.start)) % 1440;
    final duration = Duration(minutes: shiftMinutes == 0 ? 1440 : shiftMinutes);
    return (elapsedAt(now).inSeconds / duration.inSeconds).clamp(0.0, 1.0);
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
          branchId: json['branchId'] as String?,
          branchName: json['branchName'] as String?,
          id: json['id'] as String,
          workDate: json['workDate'] as String,
          checkIn: DateTime.parse(json['checkIn'] as String),
          checkOut: json['checkOut'] == null
              ? null
              : DateTime.parse(json['checkOut'] as String),
          timezone: json['timezone'] as String,
          schedule:
              WorkSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
          status: json['status'] as String?,
          location: json['location'] == null
              ? null
              : AttendanceLocation.fromJson(
                  json['location'] as Map<String, dynamic>));
}

class AttendanceSnapshot extends Equatable {
  @override
  List<Object?> get props => [workDate, records, schedule, policy, requests];

  const AttendanceSnapshot(
      {required this.workDate,
      required this.records,
      required this.schedule,
      required this.policy,
      this.requests = const []});
  final List<EmployeeRequest> requests;
  final String workDate;
  final List<AttendanceRecord> records;
  final WorkSchedule schedule;
  final AttendancePolicy policy;
  AttendanceRecord? get open => current?.checkOut == null ? current : null;
  AttendanceRecord? get current =>
      records.where((r) => r.workDate == workDate).firstOrNull;
  AttendanceRecord? get olderOpen => records
      .where((r) => r.checkOut == null && r.workDate.compareTo(workDate) < 0)
      .firstOrNull;
  bool hasPendingForgottenCheckout(AttendanceRecord record) =>
      requests.any((request) =>
          request.type == 'forgotten-check-out' &&
          request.attendanceId == record.id &&
          request.status == 'pending');
  AttendanceRecord? get blockingOlderOpen => records
      .where((record) =>
          record.checkOut == null &&
          record.workDate.compareTo(workDate) < 0 &&
          !hasPendingForgottenCheckout(record))
      .firstOrNull;
  bool get canSubmit =>
      current != null ? current!.checkOut == null : blockingOlderOpen == null;
  bool get awaitingForgottenApproval =>
      current == null && olderOpen != null && canSubmit;
  factory AttendanceSnapshot.fromJson(
          Map<String, dynamic> json, AttendancePolicy policy,
          {List<EmployeeRequest> requests = const []}) =>
      AttendanceSnapshot(
          workDate: json['workDate'] as String,
          requests: requests,
          records: (json['records'] as List)
              .map((r) => AttendanceRecord.fromJson(r as Map<String, dynamic>))
              .toList(),
          schedule:
              WorkSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
          policy: policy);
}

class AttendanceCapture {
  const AttendanceCapture(
      {required this.latitude,
      required this.longitude,
      required this.accuracyMeters,
      required this.capturedAt,
      required this.photo});
  final double latitude, longitude, accuracyMeters;
  final DateTime capturedAt;
  final Uint8List photo;
}

class AttendanceEvidence {
  const AttendanceEvidence(
      {required this.event,
      required this.latitude,
      required this.longitude,
      required this.accuracyMeters,
      required this.distanceMeters,
      required this.capturedAt,
      required this.submittedAt,
      required this.photo});
  final String event;
  final double latitude, longitude, accuracyMeters, distanceMeters;
  final DateTime capturedAt, submittedAt;
  final Uint8List photo;
}

List<AttendanceRecord> filterAttendance(List<AttendanceRecord> records,
        {String? from, String? to, String? status}) =>
    records
        .where((record) =>
            (from == null || record.workDate.compareTo(from) >= 0) &&
            (to == null || record.workDate.compareTo(to) <= 0) &&
            (status == null || record.status == status))
        .toList();
