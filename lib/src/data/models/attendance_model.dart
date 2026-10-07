import 'dart:typed_data';
import 'user_model.dart';

class AttendancePolicy {
  const AttendancePolicy(
      {required this.latitude,
      required this.longitude,
      required this.radiusMeters,
      required this.maxAccuracyMeters,
      required this.maxCaptureAgeSeconds,
      required this.maxPhotoBytes,
      required this.photoFormats});
  final double latitude, longitude, radiusMeters, maxAccuracyMeters;
  final int maxCaptureAgeSeconds, maxPhotoBytes;
  final List<String> photoFormats;
  factory AttendancePolicy.fromJson(Map<String, dynamic> json) =>
      AttendancePolicy(
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
          radiusMeters: (json['radiusMeters'] as num).toDouble(),
          maxAccuracyMeters: (json['maxAccuracyMeters'] as num).toDouble(),
          maxCaptureAgeSeconds: json['maxCaptureAgeSeconds'] as int,
          maxPhotoBytes: json['maxPhotoBytes'] as int,
          photoFormats: (json['photoFormats'] as List).cast<String>());
}

class AttendanceRecord {
  const AttendanceRecord(
      {required this.id,
      required this.workDate,
      required this.checkIn,
      required this.checkOut,
      required this.timezone,
      required this.schedule,
      this.status});
  final String id, workDate, timezone;
  final DateTime checkIn;
  final DateTime? checkOut;
  final WorkSchedule schedule;
  final String? status;
  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
          id: json['id'] as String,
          workDate: json['workDate'] as String,
          checkIn: DateTime.parse(json['checkIn'] as String),
          checkOut: json['checkOut'] == null
              ? null
              : DateTime.parse(json['checkOut'] as String),
          timezone: json['timezone'] as String,
          schedule:
              WorkSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
          status: json['status'] as String?);
}

class AttendanceSnapshot {
  const AttendanceSnapshot(
      {required this.workDate,
      required this.records,
      required this.schedule,
      required this.policy});
  final String workDate;
  final List<AttendanceRecord> records;
  final WorkSchedule schedule;
  final AttendancePolicy policy;
  AttendanceRecord? get current =>
      records.where((r) => r.workDate == workDate).firstOrNull;
  AttendanceRecord? get olderOpen => records
      .where((r) => r.checkOut == null && r.workDate != workDate)
      .firstOrNull;
  bool get canSubmit =>
      olderOpen == null && (current == null || current!.checkOut == null);
  factory AttendanceSnapshot.fromJson(
          Map<String, dynamic> json, AttendancePolicy policy) =>
      AttendanceSnapshot(
          workDate: json['workDate'] as String,
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
