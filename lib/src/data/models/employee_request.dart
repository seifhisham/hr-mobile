import 'package:equatable/equatable.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:timezone/timezone.dart' as tz;
import 'attendance_model.dart';
import 'user_model.dart';

const requestTypes = [
  'leave',
  'sick',
  'unpaid',
  'urgent',
  'excuse',
  'mission',
  'holiday',
  'forgotten-check-out'
];
const requestStatuses = ['pending', 'approved', 'rejected', 'withdrawn'];
const excuseTypes = ['leaving-early', 'arriving-late', 'during-shift'];

class RequestAttachment extends Equatable {
  static const maxBytes = 5 * 1024 * 1024;
  @override
  List<Object?> get props => [name, mimeType, content];

  const RequestAttachment(
      {required this.name, required this.mimeType, required this.content});
  final String name, mimeType, content;
  factory RequestAttachment.fromJson(Map<String, dynamic> json) =>
      RequestAttachment(
          name: json['name'] as String,
          mimeType: json['mimeType'] as String,
          content: json['content'] as String);
  Map<String, dynamic> toJson() =>
      {'name': name.trim(), 'mimeType': mimeType, 'content': content};
  Uint8List decode() {
    if (name.trim().isEmpty ||
        name.trim().length > 200 ||
        content.length > ((maxBytes + 2) ~/ 3) * 4 ||
        !RegExp(r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$')
            .hasMatch(content)) {
      throw const FormatException('requests.attachment_invalid');
    }
    final bytes = base64Decode(content);
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        !switch (mimeType) {
          'application/pdf' => bytes.length >= 5 &&
              ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-',
          'image/png' => bytes.length >= 8 &&
              bytes.take(8).join(',') == '137,80,78,71,13,10,26,10',
          'image/jpeg' => bytes.length >= 3 &&
              bytes[0] == 255 &&
              bytes[1] == 216 &&
              bytes[2] == 255,
          _ => false,
        }) {
      throw const FormatException('requests.attachment_invalid');
    }
    return bytes;
  }
}

sealed class RequestSubmission {
  const RequestSubmission(this.reason);
  final String reason;
  Map<String, dynamic> toJson();
  String? validate(AppUser user, {AttendanceRecord? attendance, DateTime? now});
  String? reasonError({bool optional = false}) =>
      reason.trim().length > (optional ? 120 : 500) ||
              (!optional && reason.trim().length < 5)
          ? 'requests.reason_invalid'
          : null;
}

final class DateRangeRequest extends RequestSubmission {
  const DateRangeRequest(
      {required this.type,
      required this.from,
      required this.to,
      required String reason,
      this.attachments = const []})
      : super(reason);
  final String type, from, to;
  final List<RequestAttachment> attachments;
  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'from': from,
        'to': to,
        'reason': reason.trim(),
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList()
      };
  @override
  String? validate(AppUser user,
          {AttendanceRecord? attendance, DateTime? now}) =>
      !requestTypes.take(7).where((type) => type != 'excuse').contains(type)
          ? 'requests.type_invalid'
          : validateRange(from, to, user.employee?.startDate) ??
              reasonError() ??
              validateAttachments(attachments);
}

final class ExcuseRequest extends RequestSubmission {
  const ExcuseRequest(
      {required this.from,
      required this.to,
      required this.durationMinutes,
      required this.excuseType,
      required this.shiftId,
      String reason = '',
      this.attachments = const []})
      : super(reason);
  final String from, to, excuseType, shiftId;
  final int durationMinutes;
  final List<RequestAttachment> attachments;
  @override
  Map<String, dynamic> toJson() => {
        'type': 'excuse',
        'from': from,
        'to': to,
        'durationMinutes': durationMinutes,
        'excuseType': excuseType,
        'shiftId': shiftId,
        'reason': reason.trim(),
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList()
      };
  @override
  String? validate(AppUser user,
      {AttendanceRecord? attendance, DateTime? now}) {
    final range = validateRange(from, to, user.employee?.startDate);
    if (range != null) return range;
    if (user.schedule == null ||
        shiftId != user.employee?.scheduleId ||
        shiftId != user.schedule!.id) {
      return 'requests.schedule_required';
    }
    if (!excuseTypes.contains(excuseType) ||
        durationMinutes < 1 ||
        durationMinutes > 1440 ||
        durationMinutes > shiftMinutes(user.schedule!)) {
      return 'requests.duration_invalid';
    }
    return reasonError(optional: true) ?? validateAttachments(attachments);
  }
}

final class ForgottenCheckOutRequest extends RequestSubmission {
  const ForgottenCheckOutRequest(
      {required this.attendanceId,
      required this.proposedCheckOut,
      required String reason})
      : super(reason);
  final String attendanceId;
  final DateTime proposedCheckOut;
  @override
  Map<String, dynamic> toJson() => {
        'type': 'forgotten-check-out',
        'attendanceId': attendanceId,
        'proposedCheckOut': proposedCheckOut.toUtc().toIso8601String(),
        'reason': reason.trim()
      };
  @override
  String? validate(AppUser user,
      {AttendanceRecord? attendance, DateTime? now}) {
    if (attendance == null ||
        attendance.id != attendanceId ||
        attendance.checkOut != null) {
      return 'requests.open_record_required';
    }
    if (proposedCheckOut.isBefore(attendance.checkIn) ||
        proposedCheckOut.isAfter(now ?? DateTime.now())) {
      return 'requests.departure_invalid';
    }
    return reasonError();
  }
}

String? validateRange(String from, String to, String? employmentStart) {
  DateTime? parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final date = DateTime.tryParse('${value}T00:00:00Z');
    return date != null && date.toIso8601String().startsWith(value)
        ? date
        : null;
  }

  final start = parse(from), end = parse(to);
  if (start == null ||
      end == null ||
      end.isBefore(start) ||
      end.difference(start).inDays > 92) {
    return 'requests.range_invalid';
  }
  if (employmentStart == null || from.compareTo(employmentStart) < 0) {
    return 'requests.before_employment';
  }
  return null;
}

int shiftMinutes(WorkSchedule schedule) {
  int minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  final length =
      (minutes(schedule.end) - minutes(schedule.start) + 1440) % 1440;
  return length == 0 ? 1440 : length;
}

String? validateAttachments(List<RequestAttachment> attachments) {
  if (attachments.length > 3) return 'requests.attachment_limit';
  try {
    for (final file in attachments) {
      file.decode();
    }
  } on FormatException {
    return 'requests.attachment_invalid';
  }
  return null;
}

// Enumerate real instants: a clock change can make a local minute occur twice or never.
List<DateTime> departureInstants(
    DateTime date, int hour, int minute, String timezone) {
  final location = tz.getLocation(timezone);
  final wall = DateTime.utc(date.year, date.month, date.day, hour, minute);
  final result = <DateTime>[];
  for (final offset in location.zones.map((zone) => zone.offset).toSet()) {
    final candidate = wall.subtract(offset);
    final local = tz.TZDateTime.from(candidate, location);
    if (local.year == date.year &&
        local.month == date.month &&
        local.day == date.day &&
        local.hour == hour &&
        local.minute == minute) {
      result.add(candidate);
    }
  }
  return result..sort();
}

class RequestReview extends Equatable {
  @override
  List<Object?> get props => [status, by, reason, employeeId, department, at];

  RequestReview.fromJson(Map<String, dynamic> json)
      : status = json['status'] as String,
        by = json['reviewedBy'] as String,
        at = DateTime.parse(json['reviewedAt'] as String),
        reason = json['reason'] as String,
        employeeId = json['employeeId'] as String?,
        department = json['department'] as String?;
  final String status, by, reason;
  final String? employeeId, department;
  final DateTime at;
}

class RequestChange extends Equatable {
  @override
  List<Object?> get props => [action, by, reason, at];

  RequestChange.fromJson(Map<String, dynamic> json)
      : action = json['action'] as String,
        by = json['by'] as String,
        at = DateTime.parse(json['at'] as String),
        reason = json['reason'] as String;
  final String action, by, reason;
  final DateTime at;
}

class EmployeeRequest extends Equatable {
  @override
  List<Object?> get props => [
        id,
        employeeId,
        employeeName,
        nationalId,
        type,
        status,
        reason,
        from,
        to,
        excuseType,
        shiftId,
        attendanceId,
        decidedBy,
        decisionReason,
        managerStage,
        managerEmployeeId,
        managerDepartment,
        durationMinutes,
        submittedAt,
        proposedCheckOut,
        decidedAt,
        salaryDeductionDays,
        managerReview,
        lastChange,
        attendance,
        attachments
      ];

  EmployeeRequest.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        employeeId = json['employeeId'] as String,
        employeeName = json['employeeName'] as String,
        nationalId = json['nationalId'] as String,
        type = json['type'] as String,
        status = json['status'] as String,
        reason = json['reason'] as String? ?? '',
        from = json['from'] as String?,
        to = json['to'] as String?,
        durationMinutes = json['durationMinutes'] as int?,
        excuseType = json['excuseType'] as String?,
        shiftId = json['shiftId'] as String?,
        attendanceId = json['attendanceId'] as String?,
        proposedCheckOut = _date(json['proposedCheckOut']),
        submittedAt = DateTime.parse(json['submittedAt'] as String),
        decidedAt = _date(json['decidedAt']),
        decidedBy = json['decidedBy'] as String?,
        decisionReason = json['decisionReason'] as String?,
        salaryDeductionDays = json['salaryDeductionDays'] as num?,
        managerStage = json['managerStage'] as String?,
        managerEmployeeId = json['managerEmployeeId'] as String?,
        managerDepartment = json['managerDepartment'] as String?,
        managerReview = json['managerReview'] == null
            ? null
            : RequestReview.fromJson(
                json['managerReview'] as Map<String, dynamic>),
        lastChange = json['lastChange'] == null
            ? null
            : RequestChange.fromJson(
                json['lastChange'] as Map<String, dynamic>),
        attendance = json['attendance'] == null
            ? null
            : AttendanceRecord.fromJson(
                json['attendance'] as Map<String, dynamic>),
        attachments = (json['attachments'] as List? ?? [])
            .map((a) => RequestAttachment.fromJson(a as Map<String, dynamic>))
            .toList();
  final String id, employeeId, employeeName, nationalId, type, status, reason;
  final String? from,
      to,
      excuseType,
      shiftId,
      attendanceId,
      decidedBy,
      decisionReason,
      managerStage,
      managerEmployeeId,
      managerDepartment;
  final int? durationMinutes;
  final DateTime submittedAt;
  final DateTime? proposedCheckOut, decidedAt;
  final num? salaryDeductionDays;
  final RequestReview? managerReview;
  final RequestChange? lastChange;
  final AttendanceRecord? attendance;
  final List<RequestAttachment> attachments;
  bool canReview(String? reviewerId) =>
      reviewerId != null &&
      employeeId != reviewerId &&
      managerEmployeeId == reviewerId &&
      status == 'pending' &&
      managerStage == 'pending';
  bool get canWithdraw => status == 'pending' && requestTypes.contains(type);
  bool matches(RequestSubmission submission) {
    final input = submission.toJson();
    if (input['type'] != type || input['reason'] != reason.trim()) return false;
    final fieldsMatch = switch (submission) {
      DateRangeRequest() => from == submission.from && to == submission.to,
      ExcuseRequest() => from == submission.from &&
          to == submission.to &&
          durationMinutes == submission.durationMinutes &&
          excuseType == submission.excuseType &&
          shiftId == submission.shiftId,
      ForgottenCheckOutRequest() => attendanceId == submission.attendanceId &&
          proposedCheckOut == submission.proposedCheckOut.toUtc(),
    };
    final expected = switch (submission) {
      DateRangeRequest(:final attachments) ||
      ExcuseRequest(:final attachments) =>
        attachments,
      ForgottenCheckOutRequest() => <RequestAttachment>[],
    };
    return fieldsMatch &&
        jsonEncode(attachments.map((a) => a.toJson()).toList()) ==
            jsonEncode(expected.map((a) => a.toJson()).toList());
  }
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

List<EmployeeRequest> filterRequests(List<EmployeeRequest> items,
        {String? status, String? type}) =>
    items
        .where((item) =>
            (status == null || item.status == status) &&
            (type == null || item.type == type))
        .toList();
