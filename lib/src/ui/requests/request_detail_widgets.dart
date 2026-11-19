import 'package:hodour/src/imports/imports.dart';

IconData requestTypeIcon(String type) => switch (type) {
      'leave' => Icons.beach_access_outlined,
      'sick' => Icons.sick_outlined,
      'unpaid' => Icons.money_off_rounded,
      'urgent' => Icons.priority_high_rounded,
      'excuse' => Icons.more_time_rounded,
      'mission' => Icons.work_outline_rounded,
      'holiday' => Icons.event_available_outlined,
      _ => Icons.logout_rounded,
    };

/// Each request type has its own accent so it is recognisable at a glance
/// everywhere it appears (type picker, form, list, details).
Color requestTypeColor(BuildContext context, String type) => switch (type) {
      'leave' => context.appColors.success,
      'sick' => context.colors.error,
      'unpaid' => context.colors.secondary,
      'urgent' => context.appColors.warning,
      'excuse' || 'forgotten-check-out' => context.appColors.info,
      'mission' => context.colors.primary,
      'holiday' => context.colors.tertiary,
      _ => context.colors.primary,
    };

/// Inclusive number of calendar days in a `yyyy-MM-dd` range, or null when
/// either end is missing or malformed.
int? requestDayCount(String? from, String? to) {
  final start = from == null ? null : DateTime.tryParse(from);
  final end = to == null ? null : DateTime.tryParse(to);
  if (start == null || end == null || end.isBefore(start)) return null;
  return DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
      1;
}

String requestDaysLabel(int days) => days == 1
    ? 'requests.day_one'.tr()
    : 'requests.day_other'.tr(namedArgs: {'count': '$days'});

/// The type's icon on a tinted tile in its accent colour.
class RequestTypeBadge extends StatelessWidget {
  const RequestTypeBadge({super.key, required this.type, this.size = 24});
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = requestTypeColor(context, type);
    return ExcludeSemantics(
        child: Container(
            padding: EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: AppBorders.md),
            child: Icon(requestTypeIcon(type), size: size, color: color)));
  }
}

/// Top of a new-request form: names the request, says what it is for, and
/// carries the type's colour so each form feels like its own request.
class RequestTypeBanner extends StatelessWidget {
  const RequestTypeBanner(
      {super.key, required this.type, required this.title, required this.tagline});
  final String type, title, tagline;

  @override
  Widget build(BuildContext context) {
    final color = requestTypeColor(context, type);
    return Container(
        padding: EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: AppBorders.lg,
            border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Row(children: [
          RequestTypeBadge(type: type, size: 28),
          SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Semantics(
                    header: true,
                    child: Text(title,
                        style: context.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700))),
                SizedBox(height: AppSpacing.xxs),
                Text(tagline,
                    style: context.textTheme.bodyMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
              ])),
        ]));
  }
}

Color requestStatusColor(BuildContext context, String status) =>
    switch (status) {
      'approved' => context.appColors.success,
      'rejected' => context.colors.error,
      'pending' => context.appColors.warning,
      _ => context.colors.onSurfaceVariant,
    };

BoxDecoration _panelDecoration(BuildContext context, {Color? color}) =>
    BoxDecoration(
        color: color ?? context.colors.surfaceContainerLow,
        borderRadius: AppBorders.lg,
        border: Border.all(color: context.colors.outlineVariant));

/// Top of the page: what the request is, who it is from, and its status.
class RequestSummaryCard extends StatelessWidget {
  const RequestSummaryCard({
    super.key,
    required this.typeLabel,
    required this.type,
    required this.statusLabel,
    required this.status,
    required this.submitted,
    required this.timezone,
    this.employeeName,
  });

  final String type, typeLabel, status, statusLabel, submitted, timezone;
  final String? employeeName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = requestStatusColor(context, status);
    return Container(
        padding: EdgeInsets.all(AppSpacing.md),
        decoration: _panelDecoration(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            RequestTypeBadge(type: type),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (employeeName != null) ...[
                    Row(children: [
                      ExcludeSemantics(
                          child: Icon(Icons.person_outline_rounded,
                              size: 16, color: colors.onSurfaceVariant)),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(
                          child: Text(employeeName!,
                              style: context.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant))),
                    ]),
                    SizedBox(height: AppSpacing.xxs),
                  ],
                  Text(typeLabel,
                      style: context.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ])),
          ]),
          SizedBox(height: AppSpacing.md),
          Row(children: [
            Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: AppBorders.full),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle)),
                  SizedBox(width: AppSpacing.sm),
                  Text(statusLabel,
                      style: context.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ])),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Text(submitted,
                    textAlign: TextAlign.end,
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant))),
          ]),
          SizedBox(height: AppSpacing.xs),
          Text('requests.times_in'.tr(namedArgs: {'timezone': timezone}),
              style: context.textTheme.labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ]));
  }
}

/// A titled block of content.
class RequestPanel extends StatelessWidget {
  const RequestPanel(
      {super.key,
      required this.title,
      required this.icon,
      required this.child,
      this.accent});
  final String title;
  final IconData icon;
  final Widget child;

  /// Tints the icon with the request type's colour.
  final Color? accent;

  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: _panelDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ExcludeSemantics(
              child: Icon(icon,
                  size: 20, color: accent ?? context.colors.primary)),
          SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Semantics(
                  header: true,
                  child: Text(title,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)))),
        ]),
        SizedBox(height: AppSpacing.md),
        child,
      ]));
}

/// One label-over-value fact, e.g. "Dates / 2026-11-20 – 2026-11-22".
class RequestFact extends StatelessWidget {
  const RequestFact(
      {super.key, required this.label, required this.value, this.icon});
  final String label, value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          ExcludeSemantics(
              child:
                  Icon(icon, size: 20, color: context.colors.onSurfaceVariant)),
          SizedBox(width: AppSpacing.md),
        ],
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: context.textTheme.labelMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
              SizedBox(height: AppSpacing.xxs),
              Text(value, style: context.textTheme.bodyLarge),
            ])),
      ]));
}

/// The employee's own words, set apart from the structured facts.
class RequestReasonBlock extends StatelessWidget {
  const RequestReasonBlock({super.key, required this.label, required this.text});
  final String label, text;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: AppBorders.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: context.textTheme.labelMedium
                ?.copyWith(color: context.colors.onSurfaceVariant)),
        SizedBox(height: AppSpacing.xs),
        Text(text, style: context.textTheme.bodyLarge),
      ]));
}

enum RequestNoticeTone { info, warning, error }

/// A short message with an icon; replaces bare coloured text.
class RequestNotice extends StatelessWidget {
  const RequestNotice(
      {super.key, required this.message, this.tone = RequestNoticeTone.info});
  final String message;
  final RequestNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      RequestNoticeTone.info => context.appColors.info,
      RequestNoticeTone.warning => context.appColors.warning,
      RequestNoticeTone.error => context.colors.error,
    };
    final icon = switch (tone) {
      RequestNoticeTone.info => Icons.info_outline_rounded,
      RequestNoticeTone.warning => Icons.warning_amber_rounded,
      RequestNoticeTone.error => Icons.error_outline_rounded,
    };
    return Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppBorders.md,
            border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Icon(icon, color: color)),
          SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message, style: context.textTheme.bodyMedium)),
        ]));
  }
}

/// One stage of the request's journey (submitted, manager, HR, ...).
class RequestTimelineStep extends StatelessWidget {
  const RequestTimelineStep({
    super.key,
    required this.title,
    required this.headline,
    required this.color,
    required this.icon,
    this.lines = const [],
    this.note,
    this.isLast = false,
  });

  final String title, headline;
  final Color color;
  final IconData icon;
  final List<String> lines;
  final String? note;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.onSurfaceVariant;
    return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
          width: 32,
          child: Column(children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle),
                child: ExcludeSemantics(child: Icon(icon, size: 18, color: color))),
            if (!isLast)
              Expanded(
                  child: Container(
                      width: 2,
                      margin: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      color: context.colors.outlineVariant)),
          ])),
      SizedBox(width: AppSpacing.md),
      Expanded(
          child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: context.textTheme.labelMedium
                            ?.copyWith(color: muted)),
                    SizedBox(height: AppSpacing.xxs),
                    Text(headline,
                        style: context.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    for (final line in lines)
                      Padding(
                          padding: EdgeInsets.only(top: AppSpacing.xxs),
                          child: Text(line,
                              style: context.textTheme.bodyMedium
                                  ?.copyWith(color: muted))),
                    if (note != null)
                      Padding(
                          padding: EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(note!,
                              style: context.textTheme.bodySmall
                                  ?.copyWith(color: muted))),
                  ]))),
    ]));
  }
}
