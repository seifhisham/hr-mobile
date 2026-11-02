import 'package:hodour/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import 'sales_widgets.dart';
import '../../theme/theme_toggle_button.dart';
import '../notifications/notification_button.dart';

class SalesPageHeading extends StatelessWidget {
  const SalesPageHeading({super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        const SalesIconTile(icon: Icons.home_work_outlined),
        SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Semantics(
                header: true,
                child: Text('sales.title'.tr(),
                    style: context.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)))),
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

class SalesWorkflowHero extends StatelessWidget {
  const SalesWorkflowHero({super.key, required this.onRecord});
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) => AppCard(
        color: context.colors.primaryContainer,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('sales.record_heading'.tr(),
              style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.colors.onPrimaryContainer)),
          SizedBox(height: AppSpacing.sm),
          Text('sales.workflow_hint'.tr(),
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onPrimaryContainer)),
          SizedBox(height: AppSpacing.md),
          AppButton(
              label: 'sales.register'.tr(),
              prefixIcon:
                  const ExcludeSemantics(child: Icon(Icons.add_rounded)),
              onPressed: onRecord),
          SalesDisclosure(
              title: 'sales.how_it_works'.tr(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (icon, key) in [
                    (Icons.edit_note_outlined, 'sales.step_record'),
                    (Icons.fact_check_outlined, 'sales.step_review'),
                    (Icons.verified_outlined, 'sales.step_counted'),
                  ])
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                              child: Icon(icon,
                                  color: context.colors.onPrimaryContainer)),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                              child: Text(key.tr(),
                                  style: context.textTheme.bodyMedium?.copyWith(
                                      color:
                                          context.colors.onPrimaryContainer))),
                        ],
                      ),
                    ),
                ],
              )),
        ]),
      );
}

class SalesMonthlySnapshot extends StatelessWidget {
  const SalesMonthlySnapshot(
      {super.key, required this.row, this.team = false, this.onShowReturned});
  final SalesPerformance row;
  final bool team;
  final VoidCallback? onShowReturned;

  @override
  Widget build(BuildContext context) => AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SalesSectionHeading(
              title: team ? row.employeeName : 'sales.verified_work'.tr(),
              icon: team ? Icons.badge_outlined : Icons.insights_outlined),
          if (team)
            Text(row.employeeNumber, style: context.textTheme.bodySmall),
          SizedBox(height: AppSpacing.sm),
          Text('sales.verified_results_hint'.tr(),
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
          SizedBox(height: AppSpacing.md),
          LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 260 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final metrics = [
              _metric(context, 'sales.meeting_total', row.meetingTotal),
              _metric(context, 'sales.deals', row.deals),
            ];
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        metrics.first,
                        SizedBox(height: AppSpacing.sm),
                        metrics.last
                      ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: metrics.first),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: metrics.last)
                  ]);
          }),
          SizedBox(height: AppSpacing.md),
          const AppDivider(),
          SizedBox(height: AppSpacing.sm),
          Text(
              'sales.review_counts'.tr(namedArgs: {
                'pending': '${row.pending}',
                'returned': '${row.returned}'
              }),
              style: context.textTheme.bodyMedium),
          if (row.returned > 0) ...[
            SizedBox(height: AppSpacing.sm),
            Text(
                (team ? 'sales.returned_team_action' : 'sales.returned_action')
                    .tr(),
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.error)),
            if (onShowReturned != null)
              AppTextButton(
                  label: 'sales.show_returned'.tr(), onPressed: onShowReturned),
          ],
        ]),
      );

  Widget _metric(BuildContext context, String label, int value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600, color: context.colors.primary)),
          Text(label.tr(), style: context.textTheme.bodyMedium),
        ],
      );
}
