import 'package:hodour/src/imports/imports.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/admin_dashboard.dart';

enum DashboardTone { neutral, good, waiting, attention }

/// A titled card grouping one dashboard topic.
class DashboardSection extends StatelessWidget {
  const DashboardSection(
      {super.key,
      required this.title,
      required this.icon,
      required this.child,
      this.subtitle,
      this.action});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              header: true,
              child: Row(children: [
                ExcludeSemantics(
                    child: Container(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                      color: context.colors.primaryContainer,
                      borderRadius: AppBorders.md),
                  child: Icon(icon,
                      size: 20, color: context.colors.onPrimaryContainer),
                )),
                SizedBox(width: AppSpacing.ms),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: context.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant)),
                    ])),
                if (action != null) action!,
              ]),
            ),
            SizedBox(height: AppSpacing.md),
            child,
          ]),
        ),
      );
}

/// A number with a label; tinted when it needs attention.
class DashboardMetric extends StatelessWidget {
  const DashboardMetric(
      {super.key,
      required this.label,
      required this.value,
      this.tone = DashboardTone.neutral,
      this.caption});
  final String label;
  final String value;
  final String? caption;
  final DashboardTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appColors = context.appColors;
    final (background, accent) = switch (tone) {
      DashboardTone.attention => (
          colors.errorContainer,
          colors.onErrorContainer
        ),
      DashboardTone.waiting => (
          colors.secondaryContainer,
          colors.onSecondaryContainer
        ),
      DashboardTone.good => (colors.surfaceContainerHighest, appColors.success),
      DashboardTone.neutral => (colors.surfaceContainerHighest, colors.primary),
    };
    final text =
        tone == DashboardTone.attention || tone == DashboardTone.waiting
            ? accent
            : colors.onSurface;
    return Semantics(
      label: '$label: $value${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(AppSpacing.md),
        decoration:
            BoxDecoration(color: background, borderRadius: AppBorders.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: context.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: accent)),
          ),
          Text(label,
              style: context.textTheme.bodySmall?.copyWith(color: text)),
          if (caption != null)
            Text(caption!,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: text.withValues(alpha: 0.75))),
        ]),
      ),
    );
  }
}

/// Lays children out two per row (one per row on narrow or zoomed layouts),
/// with equal heights within a row.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final single = box.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        final gap = AppSpacing.sm;
        if (single) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  children[i],
                ]
              ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i += 2) ...[
                if (i > 0) SizedBox(height: gap),
                IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Expanded(child: children[i]),
                      SizedBox(width: gap),
                      Expanded(
                          child: i + 1 < children.length
                              ? children[i + 1]
                              : const SizedBox.shrink()),
                    ])),
              ]
            ]);
      });
}

/// A small read-only label, e.g. a count per request type.
class DashboardTag extends StatelessWidget {
  const DashboardTag({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.ms, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
            color: context.colors.secondaryContainer,
            borderRadius: AppBorders.full),
        child: Text(label,
            style: context.textTheme.labelMedium?.copyWith(
                color: context.colors.onSecondaryContainer,
                fontWeight: FontWeight.w600)),
      );
}

/// A labelled progress bar with a trailing percentage.
class DashboardRate extends StatelessWidget {
  const DashboardRate(
      {super.key,
      required this.label,
      required this.value,
      this.detail,
      this.color});
  final String label;
  final double? value;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final rate = value;
    final barColor = color ??
        (rate == null
            ? context.colors.outline
            : rate >= 0.9
                ? context.appColors.success
                : rate >= 0.7
                    ? context.appColors.warning
                    : context.colors.error);
    return Semantics(
      label: '$label: ${percentLabel(rate)}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: context.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis)),
          if (detail != null) ...[
            Text(detail!,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant)),
            SizedBox(width: AppSpacing.sm),
          ],
          Text(percentLabel(rate),
              style: context.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        SizedBox(height: AppSpacing.xs),
        AppProgressBar(
            value: rate ?? 0, minHeight: AppSpacing.sm, color: barColor),
      ]),
    );
  }
}

/// Daily attendance bars for the loaded week: full bar is expected staff,
/// filled part is arrivals, with late arrivals shaded.
class AttendanceTrendChart extends StatelessWidget {
  const AttendanceTrendChart(
      {super.key, required this.days, required this.today});
  final List<DaySnapshot> days;
  final String today;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toLanguageTag();
    // Room for the bars plus two label lines at the current text scale.
    final labels = MediaQuery.textScalerOf(context)
            .scale(context.textTheme.labelSmall?.fontSize ?? 11) *
        3;
    final height = AppSpacing.xxxl + AppSpacing.xl + labels;
    final colors = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: height + AppSpacing.sm,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final day in days)
            Expanded(
              child: Semantics(
                label: '${_weekday(day.date, locale)}: '
                    '${'admin.trend_semantics'.tr(namedArgs: {
                      'present': '${day.present}',
                      'expected': '${day.scheduled - day.onLeave}',
                      'late': '${day.late}'
                    })}',
                excludeSemantics: true,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(percentLabel(day.attendanceRate, compact: true),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: context.textTheme.labelSmall),
                        SizedBox(height: AppSpacing.xs),
                        Expanded(
                            child: _Bar(
                                rate: day.attendanceRate ?? 0,
                                lateShare: day.present == 0
                                    ? 0
                                    : day.late / day.present,
                                highlight: day.date == today)),
                        SizedBox(height: AppSpacing.xs),
                        Text(_weekday(day.date, locale),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: context.textTheme.labelSmall?.copyWith(
                                fontWeight: day.date == today
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: day.date == today
                                    ? colors.primary
                                    : colors.onSurfaceVariant)),
                      ]),
                ),
              ),
            ),
        ]),
      ),
      SizedBox(height: AppSpacing.sm),
      Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.xs, children: [
        _Legend(color: colors.primary, label: 'admin.legend_on_time'.tr()),
        _Legend(
            color: context.appColors.warning, label: 'admin.legend_late'.tr()),
        _Legend(
            color: colors.surfaceContainerHighest,
            label: 'admin.legend_missing'.tr()),
      ]),
    ]);
  }

  static String _weekday(String date, String locale) {
    try {
      return DateFormat.E(locale).format(DateTime.parse(date));
    } on ArgumentError {
      return DateFormat.E().format(DateTime.parse(date));
    }
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.rate, required this.lateShare, required this.highlight});
  final double rate, lateShare;
  final bool highlight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final filled = box.maxHeight * rate.clamp(0, 1);
        final late = filled * lateShare.clamp(0, 1);
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest,
              borderRadius: AppBorders.sm,
              border: highlight
                  ? Border.all(color: context.colors.primary, width: 1.5)
                  : null),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            AnimatedContainer(
                duration: AppDurations.normal,
                curve: AppCurves.standard,
                height: late,
                color: context.appColors.warning),
            AnimatedContainer(
                duration: AppDurations.normal,
                curve: AppCurves.standard,
                height: filled - late,
                color: context.colors.primary),
          ]),
        );
      });
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: AppSpacing.ms,
            height: AppSpacing.ms,
            decoration:
                BoxDecoration(color: color, borderRadius: AppBorders.xs)),
        SizedBox(width: AppSpacing.xs),
        Text(label, style: context.textTheme.labelSmall),
      ]);
}

/// A compact list that shows the first few rows and expands on demand.
class DashboardList<T> extends StatefulWidget {
  const DashboardList(
      {super.key,
      required this.items,
      required this.itemBuilder,
      required this.emptyText,
      this.initialCount = 4});
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final int initialCount;

  @override
  State<DashboardList<T>> createState() => _DashboardListState<T>();
}

class _DashboardListState<T> extends State<DashboardList<T>> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return Row(children: [
        Icon(Icons.check_circle_outline,
            size: 18, color: context.appColors.success),
        SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text(widget.emptyText,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant))),
      ]);
    }
    final visible =
        _expanded ? items : items.take(widget.initialCount).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < visible.length; i++) ...[
        if (i > 0) const AppDivider(),
        widget.itemBuilder(context, visible[i]),
      ],
      if (items.length > widget.initialCount)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppTextButton(
              label: _expanded
                  ? 'admin.show_less'.tr()
                  : 'admin.show_all'
                      .tr(namedArgs: {'count': '${items.length}'}),
              onPressed: () => setState(() => _expanded = !_expanded)),
        ),
    ]);
  }
}

/// One person line: avatar initials, name, secondary text, trailing value.
class DashboardPersonRow extends StatelessWidget {
  const DashboardPersonRow(
      {super.key,
      required this.name,
      required this.subtitle,
      this.trailing,
      this.trailingColor});
  final String name, subtitle;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(children: [
          AppAvatar(initials: _initials(name), radius: AppSpacing.ml),
          SizedBox(width: AppSpacing.ms),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: context.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ])),
          if (trailing != null) ...[
            SizedBox(width: AppSpacing.sm),
            Text(trailing!,
                style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: trailingColor ?? context.colors.onSurface)),
          ],
        ]),
      );
}

String percentLabel(double? value, {bool compact = false}) =>
    value == null ? (compact ? '–' : '--') : '${(value * 100).round()}%';

/// `HH:mm` in the record's timezone.
String dashboardClock(DateTime? value, String timezone) {
  if (value == null) return '--';
  try {
    return DateFormat('HH:mm')
        .format(tz.TZDateTime.from(value, tz.getLocation(timezone)));
  } on tz.LocationNotFoundException {
    return '${DateFormat('HH:mm').format(value.toUtc())} UTC';
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
}
