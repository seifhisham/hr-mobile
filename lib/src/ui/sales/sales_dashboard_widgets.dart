import 'package:hodour/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';

/// Page title with the app-wide shortcuts; no decorative logo tile.
class SalesPageHeading extends StatelessWidget {
  const SalesPageHeading({super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Semantics(
                header: true,
                child: Text('sales.title'.tr(),
                    style: context.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)))),
        ThemeToggleButton(color: context.colors.onSurface),
        NotificationButton(color: context.colors.onSurface, dotBadge: true),
      ]);
}

/// Keeps secondary controls out of the main task while preserving their context.
class SalesDisclosure extends StatefulWidget {
  const SalesDisclosure(
      {super.key,
      required this.title,
      required this.child,
      this.initiallyExpanded = false});
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<SalesDisclosure> createState() => _SalesDisclosureState();
}

class _SalesDisclosureState extends State<SalesDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final content = _expanded
        ? Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm), child: widget.child)
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: _expanded,
          child: AppButton(
            variant: ButtonVariant.ghost,
            label: widget.title,
            suffixIcon: ExcludeSemantics(
                child: Icon(_expanded ? Icons.expand_less : Icons.expand_more)),
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (MediaQuery.disableAnimationsOf(context))
          content
        else
          AnimatedSize(
            duration: AppDurations.quick,
            curve: AppCurves.standard,
            alignment: AlignmentDirectional.topStart,
            child: content,
          ),
      ],
    );
  }
}

/// Previous / current / next month in one quiet bar.
class SalesMonthBar extends StatelessWidget {
  const SalesMonthBar({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onChoose,
  });
  final String label;
  final VoidCallback onPrevious, onNext, onChoose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: AppBorders.full,
          border: Border.all(color: context.colors.outlineVariant)),
      child: Row(children: [
        IconButton(
            tooltip: 'sales.previous_month'.tr(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: onPrevious),
        Expanded(
            child: Semantics(
                button: true,
                hint: 'sales.reporting_month'.tr(),
                child: AppTextButton(label: label, onPressed: onChoose))),
        IconButton(
            tooltip: 'sales.next_month'.tr(),
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            onPressed: onNext),
      ]));
}

/// The month at a glance: four numbers, no paragraphs. Awaiting and
/// returned tiles open the matching part of the history.
class SalesOverview extends StatelessWidget {
  const SalesOverview(
      {super.key, required this.row, this.team = false, this.onShowStatus});
  final SalesPerformance row;
  final bool team;
  final ValueChanged<String>? onShowStatus;

  @override
  Widget build(BuildContext context) => AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (team) ...[
            Text(row.employeeName,
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(row.employeeNumber,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant)),
            SizedBox(height: AppSpacing.md),
          ],
          LayoutBuilder(builder: (context, constraints) {
            final single = constraints.maxWidth < 260 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final gap = AppSpacing.sm;
            Widget tile(String label, int value,
                    {String? status, _Tone tone = _Tone.neutral}) =>
                _StatTile(
                    label: label,
                    value: value,
                    tone: value > 0 ? tone : _Tone.neutral,
                    onTap: status == null || value == 0 || onShowStatus == null
                        ? null
                        : () => onShowStatus!(status));
            final tiles = [
              tile('sales.meeting_total'.tr(), row.meetingTotal),
              tile('sales.deals'.tr(), row.deals),
              tile('sales.awaiting_review'.tr(), row.pending,
                  status: 'pending', tone: _Tone.waiting),
              tile('sales.returned_short'.tr(), row.returned,
                  status: 'returned', tone: _Tone.attention),
            ];
            // Tiles in a row share one height, however many lines their
            // labels need, so no box looks shorter or offset from its
            // neighbour.
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (single)
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  tiles[i],
                ]
              else
                for (var i = 0; i < tiles.length; i += 2) ...[
                  if (i > 0) SizedBox(height: gap),
                  IntrinsicHeight(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Expanded(child: tiles[i]),
                        SizedBox(width: gap),
                        Expanded(child: tiles[i + 1]),
                      ])),
                ],
            ]);
          }),
        ]),
      );
}

enum _Tone { neutral, waiting, attention }

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label,
      required this.value,
      required this.tone,
      this.onTap});
  final String label;
  final int value;
  final _Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, accent) = switch (tone) {
      _Tone.attention => (colors.errorContainer, colors.onErrorContainer),
      _Tone.waiting => (
          colors.secondaryContainer,
          colors.onSecondaryContainer
        ),
      _Tone.neutral => (colors.surfaceContainerHighest, colors.primary),
    };
    final textColor = tone == _Tone.neutral ? colors.onSurface : accent;
    return Material(
        color: background,
        borderRadius: AppBorders.md,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('$value',
                            style: context.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700, color: accent)),
                        const Spacer(),
                        if (onTap != null)
                          ExcludeSemantics(
                              child: Icon(
                                  Directionality.of(context) ==
                                          TextDirection.rtl
                                      ? Icons.chevron_left
                                      : Icons.chevron_right,
                                  size: 20,
                                  color: textColor)),
                      ]),
                      Text(label,
                          style: context.textTheme.bodySmall
                              ?.copyWith(color: textColor)),
                    ]))));
  }
}

/// A single-select row of chips (first option is usually "All").
class SalesFilterRow extends StatelessWidget {
  const SalesFilterRow(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected});

  /// `null` value means "no filter".
  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (value, label) in options) ...[
          AppChip(
              label: label,
              selected: selected == value,
              onSelected: (_) => onSelected(value)),
          SizedBox(width: AppSpacing.sm),
        ],
      ]));
}
