import 'package:equatable/equatable.dart';
import 'dart:math';

const salesKinds = ['meeting', 'viewing', 'closed-deal'];
const salesStatuses = ['pending', 'verified', 'returned'];

class SalesAccess extends Equatable {
  @override
  List<Object?> get props => [canSubmit, canReview, canSetTargets];

  const SalesAccess(
      {this.canSubmit = false,
      this.canReview = false,
      this.canSetTargets = false});
  factory SalesAccess.fromJson(Map<String, dynamic> json) => SalesAccess(
      canSubmit: json['canSubmit'] as bool,
      canReview: json['canReview'] as bool,
      canSetTargets: json['canSetTargets'] as bool);
  final bool canSubmit, canReview, canSetTargets;
}

/// Calendar dates deliberately stay strings, independent of device timezone.
bool validSalesDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
}

String newSalesId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

sealed class SalesSubmission {
  const SalesSubmission(
      {required this.activityDate,
      required this.clientName,
      this.projectName = '',
      this.propertyReference = '',
      this.notes = ''});
  final String activityDate, clientName, projectName, propertyReference, notes;
  String get kind;
  Map<String, dynamic> toJson();
  Map<String, dynamic> get common => {
        'kind': kind,
        'activityDate': activityDate,
        'clientName': clientName.trim(),
        'projectName': projectName.trim(),
        'propertyReference': propertyReference.trim(),
        'notes': notes.trim()
      };

  String? validate({required String startDate, required String today}) {
    if (!validSalesDate(activityDate) ||
        activityDate.compareTo(startDate) < 0 ||
        activityDate.compareTo(today) > 0) {
      return 'sales.errors.date';
    }
    if (clientName.trim().isEmpty ||
        clientName.trim().length > 120 ||
        projectName.trim().length > 120 ||
        propertyReference.trim().length > 120 ||
        notes.trim().length > 1000) {
      return 'sales.errors.text';
    }
    return switch (this) {
      SalesVisit(:final kind, :final purpose, :final outcome)
          when !const ['meeting', 'viewing'].contains(kind) ||
              (kind == 'viewing' && propertyReference.trim().isEmpty) ||
              purpose.trim().isEmpty ||
              purpose.trim().length > 120 ||
              outcome.trim().isEmpty ||
              outcome.trim().length > 120 =>
        'sales.errors.visit',
      SalesVisit(:final followUpDate)
          when followUpDate != null &&
              (!validSalesDate(followUpDate) ||
                  followUpDate.compareTo(activityDate) < 0) =>
        'sales.errors.follow_up',
      SalesDeal(:final dealReference, :final transactionType)
          when propertyReference.trim().isEmpty ||
              dealReference.trim().isEmpty ||
              dealReference.trim().length > 120 ||
              !const ['sale', 'lease'].contains(transactionType) =>
        'sales.errors.deal',
      SalesDeal(:final value, :final currency)
          when !value.isFinite ||
              value <= 0 ||
              value > 1000000000 ||
              (value * 100 - (value * 100).round()).abs() > 0.00001 ||
              !RegExp(r'^[A-Z]{3}$').hasMatch(currency) =>
        'sales.errors.money',
      _ => null,
    };
  }
}

final class SalesVisit extends SalesSubmission {
  const SalesVisit(
      {required this.kind,
      required super.activityDate,
      required super.clientName,
      required this.purpose,
      required this.outcome,
      this.followUpDate,
      super.projectName,
      super.propertyReference,
      super.notes});
  @override
  final String kind;
  final String purpose, outcome;
  final String? followUpDate;
  @override
  Map<String, dynamic> toJson() => {
        ...common,
        'purpose': purpose.trim(),
        'outcome': outcome.trim(),
        if (followUpDate != null) 'followUpDate': followUpDate
      };
}

final class SalesDeal extends SalesSubmission {
  const SalesDeal(
      {required super.activityDate,
      required super.clientName,
      required super.propertyReference,
      required this.dealReference,
      required this.transactionType,
      required this.value,
      required this.currency,
      super.projectName,
      super.notes});
  @override
  String get kind => 'closed-deal';
  final String dealReference, transactionType, currency;
  final num value;
  @override
  Map<String, dynamic> toJson() => {
        ...common,
        'dealReference': dealReference.trim(),
        'transactionType': transactionType,
        'value': value,
        'currency': currency
      };
}

class SalesReview extends Equatable {
  @override
  List<Object?> get props => [status, reason, by, byId, at];

  SalesReview.fromJson(Map<String, dynamic> json)
      : status = json['status'] as String,
        reason = json['reason'] as String,
        by = json['by'] as String,
        byId = json['byId'] as String,
        at = DateTime.parse(json['at'] as String);
  final String status, reason, by, byId;
  final DateTime at;
}

class SalesActivity extends Equatable {
  @override
  List<Object?> get props => [
        id,
        employeeId,
        employeeName,
        employeeNumber,
        department,
        kind,
        status,
        activityDate,
        clientName,
        projectName,
        propertyReference,
        notes,
        purpose,
        outcome,
        followUpDate,
        dealReference,
        transactionType,
        currency,
        value,
        revision,
        canReview,
        submittedAt,
        updatedAt,
        review
      ];

  SalesActivity.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        employeeId = json['employeeId'] as String,
        employeeName = json['employeeName'] as String,
        employeeNumber = json['employeeNumber'] as String,
        department = json['department'] as String,
        kind = json['kind'] as String,
        status = json['status'] as String,
        activityDate = json['activityDate'] as String,
        clientName = json['clientName'] as String,
        projectName = json['projectName'] as String? ?? '',
        propertyReference = json['propertyReference'] as String? ?? '',
        notes = json['notes'] as String? ?? '',
        purpose = json['purpose'] as String?,
        outcome = json['outcome'] as String?,
        followUpDate = json['followUpDate'] as String?,
        dealReference = json['dealReference'] as String?,
        transactionType = json['transactionType'] as String?,
        value = json['value'] as num?,
        currency = json['currency'] as String?,
        revision = json['revision'] as int,
        canReview = json['canReview'] as bool,
        submittedAt = DateTime.parse(json['submittedAt'] as String),
        updatedAt = DateTime.parse(json['updatedAt'] as String),
        review = json['review'] == null
            ? null
            : SalesReview.fromJson(json['review'] as Map<String, dynamic>);
  final String id,
      employeeId,
      employeeName,
      employeeNumber,
      department,
      kind,
      status,
      activityDate,
      clientName,
      projectName,
      propertyReference,
      notes;
  final String? purpose,
      outcome,
      followUpDate,
      dealReference,
      transactionType,
      currency;
  final num? value;
  final int revision;
  final bool canReview;
  final DateTime submittedAt, updatedAt;
  final SalesReview? review;
  bool get supported =>
      salesKinds.contains(kind) && salesStatuses.contains(status);
  bool canCorrect(String? owner) =>
      supported &&
      employeeId == owner &&
      const ['pending', 'returned'].contains(status);
  bool canVerify(String? owner) =>
      supported && canReview && employeeId != owner && status == 'pending';
  bool canReturn(String? owner) =>
      supported &&
      canReview &&
      employeeId != owner &&
      const ['pending', 'verified'].contains(status);
  SalesSubmission get submission => kind == 'closed-deal'
      ? SalesDeal(
          activityDate: activityDate,
          clientName: clientName,
          projectName: projectName,
          propertyReference: propertyReference,
          notes: notes,
          dealReference: dealReference!,
          transactionType: transactionType!,
          value: value!,
          currency: currency!)
      : SalesVisit(
          kind: kind,
          activityDate: activityDate,
          clientName: clientName,
          projectName: projectName,
          propertyReference: propertyReference,
          notes: notes,
          purpose: purpose!,
          outcome: outcome!,
          followUpDate: followUpDate);
}

class SalesTarget extends Equatable {
  @override
  List<Object?> get props => [
        employeeId,
        month,
        reason,
        updatedBy,
        meetings,
        deals,
        transactionValue,
        currency,
        revision,
        updatedAt
      ];

  SalesTarget.fromJson(Map<String, dynamic> json)
      : employeeId = json['employeeId'] as String,
        month = json['month'] as String,
        meetings = json['meetings'] as num,
        deals = json['deals'] as num,
        transactionValue = json['transactionValue'] as num?,
        currency = json['currency'] as String?,
        revision = json['revision'] as int,
        reason = json['reason'] as String,
        updatedAt = DateTime.parse(json['updatedAt'] as String),
        updatedBy = json['updatedBy'] as String;
  final String employeeId, month, reason, updatedBy;
  final num meetings, deals;
  final num? transactionValue;
  final String? currency;
  final int revision;
  final DateTime updatedAt;
}

class SalesPerformance extends Equatable {
  @override
  List<Object?> get props => [
        employeeId,
        employeeName,
        employeeNumber,
        department,
        month,
        active,
        salesEnabled,
        meetings,
        viewings,
        meetingTotal,
        deals,
        sales,
        leases,
        pending,
        returned,
        transactionValues,
        target,
        achievement
      ];

  SalesPerformance.fromJson(Map<String, dynamic> json)
      : employeeId = json['employeeId'] as String,
        employeeName = json['employeeName'] as String,
        employeeNumber = json['employeeNumber'] as String,
        department = json['department'] as String,
        month = json['month'] as String,
        active = json['active'] as bool,
        salesEnabled = json['salesEnabled'] as bool,
        meetings = json['meetings'] as int,
        viewings = json['viewings'] as int,
        meetingTotal = json['meetingTotal'] as int,
        deals = json['deals'] as int,
        sales = json['sales'] as int,
        leases = json['leases'] as int,
        pending = json['pending'] as int,
        returned = json['returned'] as int,
        transactionValues =
            Map<String, num>.from(json['transactionValues'] as Map),
        target = json['target'] == null
            ? null
            : SalesTarget.fromJson(json['target'] as Map<String, dynamic>),
        achievement = Map<String, num?>.from(json['achievement'] as Map);
  final String employeeId, employeeName, employeeNumber, department, month;
  final bool active, salesEnabled;
  final int meetings,
      viewings,
      meetingTotal,
      deals,
      sales,
      leases,
      pending,
      returned;
  final Map<String, num> transactionValues;
  final SalesTarget? target;
  final Map<String, num?> achievement;
}
