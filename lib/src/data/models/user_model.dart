import 'package:equatable/equatable.dart';

/// /auth/me response. Calendar dates and national IDs remain text.
class AppUser extends Equatable {
  const AppUser(
      {required this.id,
      required this.email,
      required this.name,
      required this.role,
      required this.companyName,
      required this.timezone,
      required this.today,
      this.employee,
      this.schedule});
  final String id;
  final String email;
  final String name;
  final String role;
  final String companyName;
  final String timezone;
  final String today;
  final EmployeeProfile? employee;
  final WorkSchedule? schedule;

  factory AppUser.fromJson(Map<String, dynamic> json,
      {WorkSchedule? schedule}) {
    final user = json['user'] as Map<String, dynamic>;
    final company = json['company'] as Map<String, dynamic>;
    return AppUser(
        id: _text(user, 'id'),
        email: _text(user, 'email'),
        name: _text(user, 'name'),
        role: _text(user, 'role'),
        companyName: _text(company, 'name'),
        timezone: _text(company, 'timezone'),
        today: _text(json, 'today'),
        employee: json['employee'] == null
            ? null
            : EmployeeProfile.fromJson(
                json['employee'] as Map<String, dynamic>),
        schedule: schedule);
  }
  @override
  List<Object?> get props =>
      [id, email, name, role, companyName, timezone, today, employee, schedule];
}

class EmployeeProfile extends Equatable {
  const EmployeeProfile(
      {required this.id,
      required this.employeeNumber,
      required this.nationalId,
      required this.name,
      required this.email,
      required this.department,
      required this.jobTitle,
      required this.startDate,
      required this.active,
      this.scheduleId});
  final String id;
  final String employeeNumber;
  final String nationalId;
  final String name;
  final String email;
  final String department;
  final String jobTitle;
  final String startDate;
  final bool active;
  final String? scheduleId;
  factory EmployeeProfile.fromJson(Map<String, dynamic> json) =>
      EmployeeProfile(
          id: _text(json, 'id'),
          employeeNumber: _text(json, 'employeeNumber'),
          nationalId: _text(json, 'nationalId'),
          name: _text(json, 'name'),
          email: _text(json, 'email'),
          department: _text(json, 'department'),
          jobTitle: _text(json, 'jobTitle'),
          startDate: _text(json, 'startDate'),
          active: json['active'] as bool,
          scheduleId: json['scheduleId'] as String?);
  @override
  List<Object?> get props => [
        id,
        employeeNumber,
        nationalId,
        name,
        email,
        department,
        jobTitle,
        startDate,
        active,
        scheduleId
      ];
}

class WorkSchedule extends Equatable {
  const WorkSchedule(
      {required this.id,
      required this.name,
      required this.start,
      required this.end,
      required this.days,
      required this.graceMinutes});
  final String id;
  final String name;
  final String start;
  final String end;
  final List<int> days;
  final int graceMinutes;
  factory WorkSchedule.fromJson(Map<String, dynamic> json) => WorkSchedule(
      id: _text(json, 'id'),
      name: _text(json, 'name'),
      start: _text(json, 'start'),
      end: _text(json, 'end'),
      days: List<int>.unmodifiable(json['days'] as List<Object?>),
      graceMinutes: json['graceMinutes'] as int);
  @override
  List<Object?> get props => [id, name, start, end, days, graceMinutes];
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid session response');
  }
  return value;
}
