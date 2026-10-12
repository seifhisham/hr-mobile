import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../requests/request_widgets.dart' show requestTime;
import 'sales_provider.dart';

String salesKindLabel(String value) => salesKinds.contains(value)
    ? 'sales.kinds.${value.replaceAll('-', '_')}'.tr()
    : value;
String salesStatusLabel(String value) =>
    salesStatuses.contains(value) ? 'sales.statuses.$value'.tr() : value;
IconData salesKindIcon(String value) => switch (value) {
      'meeting' => Icons.groups_outlined,
      'viewing' => Icons.home_work_outlined,
      _ => Icons.handshake_outlined,
    };
String salesMoney(num value, String currency) =>
    '$currency ${NumberFormat('#,##0.00').format(value)}';
String salesDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

class SalesNotice extends StatelessWidget {
  const SalesNotice(
      {super.key, required this.text, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: context.colors.secondaryContainer,
          borderRadius: AppBorders.card),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: context.colors.onSecondaryContainer),
        SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text(text,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSecondaryContainer))),
      ]));
}

class SalesStatus extends StatelessWidget {
  const SalesStatus({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          children: [
            Icon(
                switch (status) {
                  'verified' => Icons.check_circle_outline,
                  'returned' => Icons.edit_note_rounded,
                  _ => Icons.schedule
                },
                color: status == 'verified'
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant),
            Text(salesStatusLabel(status), style: context.textTheme.labelLarge),
          ]);
}

class SalesMutationFeedback extends ConsumerWidget {
  const SalesMutationFeedback({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesMutationProvider);
    final canSubmit = accessValue(ref.watch(salesAccessProvider)).canSubmit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.notice case final key?)
        Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Semantics(
                liveRegion: true, child: SalesNotice(text: key.tr()))),
      if (state.action case RequestFailure(:final failure))
        Semantics(
            liveRegion: true,
            child: Text(failure.message,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.error))),
      if (state.pending != null) ...[
        AppButton(
            label: 'sales.check_result'.tr(),
            variant: ButtonVariant.outline,
            isLoading: state.action.isLoading,
            onPressed: state.action.isLoading
                ? null
                : () => ref.read(salesMutationProvider.notifier).reconcile()),
        if (state.pending case SalesPendingCreate(retryAllowed: true))
          AppButton(
              label: 'sales.retry_submission'.tr(),
              onPressed: state.action.isLoading || !canSubmit
                  ? null
                  : () =>
                      ref.read(salesMutationProvider.notifier).retryCreation()),
        if (state.pending case SalesPendingCreate(retryAllowed: true))
          AppTextButton(
              label: 'sales.edit_unsaved'.tr(),
              onPressed: state.action.isLoading
                  ? null
                  : () => ref
                      .read(salesMutationProvider.notifier)
                      .editUnstoredCreation()),
      ],
    ]);
  }
}

class SalesPerformanceCard extends StatelessWidget {
  const SalesPerformanceCard({super.key, required this.row, this.team = false});
  final SalesPerformance row;
  final bool team;
  @override
  Widget build(BuildContext context) => AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(team ? row.employeeName : 'sales.verified_work'.tr(),
            style: context.textTheme.titleLarge),
        if (team) Text('${row.employeeNumber} · ${row.department}'),
        SizedBox(height: AppSpacing.md),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 500 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.5
              ? 3
              : 1;
          return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final metric in [
                  (
                    'sales.meeting_total',
                    row.meetingTotal,
                    Icons.groups_outlined
                  ),
                  ('sales.deals', row.deals, Icons.handshake_outlined),
                  ('sales.awaiting_review', row.pending, Icons.schedule),
                ])
                  SizedBox(
                      width: (constraints.maxWidth -
                              (columns - 1) * AppSpacing.md) /
                          columns,
                      child: Container(
                          padding: EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                              color: context.colors.surfaceContainerLow,
                              borderRadius: AppBorders.lg),
                          child: Row(children: [
                            Icon(metric.$3, color: context.colors.primary),
                            SizedBox(width: AppSpacing.md),
                            Expanded(child: Text(metric.$1.tr())),
                            Text('${metric.$2}',
                                style: context.textTheme.headlineSmall)
                          ]))),
              ]);
        }),
        SizedBox(height: AppSpacing.md),
        Text('sales.breakdown'.tr(namedArgs: {
          'meetings': '${row.meetings}',
          'viewings': '${row.viewings}',
          'sales': '${row.sales}',
          'leases': '${row.leases}'
        })),
        SizedBox(height: AppSpacing.sm),
        Text(
            'sales.returned_count'.tr(namedArgs: {'count': '${row.returned}'})),
        SizedBox(height: AppSpacing.lg),
        Text('sales.contract_totals'.tr(),
            style: context.textTheme.titleMedium),
        if (row.transactionValues.isEmpty)
          Text('sales.no_verified_contracts'.tr()),
        for (final entry in row.transactionValues.entries)
          Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text(salesMoney(entry.value, entry.key),
                  style: context.textTheme.titleLarge)),
        SizedBox(height: AppSpacing.lg),
        Text('sales.monthly_targets'.tr(),
            style: context.textTheme.titleMedium),
        Text('sales.targets_hint'.tr(), style: context.textTheme.bodySmall),
        SizedBox(height: AppSpacing.sm),
        _target(context, 'sales.meeting_total', row.target?.meetings,
            row.achievement['meetings']),
        _target(context, 'sales.deals', row.target?.deals,
            row.achievement['deals']),
        _target(context, 'sales.contract_value', row.target?.transactionValue,
            row.achievement['transactionValue'],
            currency: row.target?.currency),
      ]));
  Widget _target(
          BuildContext context, String label, num? target, num? percentage,
          {String? currency}) =>
      Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(label.tr(), style: context.textTheme.labelLarge),
            Text(
                '${target == null ? 'sales.not_set'.tr() : currency == null ? '$target' : salesMoney(target, currency)} · '
                '${percentage == null ? 'sales.unavailable'.tr() : '${percentage.toStringAsFixed(1)}%'}'),
            if (percentage != null) ...[
              SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: (percentage / 100).clamp(0, 1)),
            ],
          ]));
}

class SalesActivityCard extends StatelessWidget {
  const SalesActivityCard(
      {super.key, required this.item, this.team = false, required this.onTap});
  final SalesActivity item;
  final bool team;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(salesKindIcon(item.kind), color: context.colors.primary),
          SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(salesKindLabel(item.kind),
                    style: context.textTheme.titleMedium),
                Text(item.clientName),
              ])),
          Icon(Directionality.of(context) == TextDirection.rtl
              ? Icons.chevron_left
              : Icons.chevron_right),
        ]),
        SizedBox(height: AppSpacing.sm),
        SalesStatus(status: item.status),
        Text(item.activityDate, style: context.textTheme.bodySmall),
        if (team) Text('${item.employeeName} · ${item.department}'),
        if (item.propertyReference.isNotEmpty) Text(item.propertyReference),
        if (item.value != null && item.currency != null)
          Text(salesMoney(item.value!, item.currency!)),
      ]));
}

class SalesDetailFields extends StatelessWidget {
  const SalesDetailFields(
      {super.key,
      required this.item,
      required this.timezone,
      this.team = false});
  final SalesActivity item;
  final String timezone;
  final bool team;
  @override
  Widget build(BuildContext context) => AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SalesStatus(status: item.status),
        SizedBox(height: AppSpacing.md),
        if (salesStatuses.contains(item.status))
          SalesNotice(text: 'sales.status_help.${item.status}'.tr()),
        if (team) ...[
          _field(context, 'sales.employee', item.employeeName),
          _field(context, 'account.employee_number', item.employeeNumber),
          _field(context, 'account.department', item.department)
        ],
        _field(context, 'sales.type', salesKindLabel(item.kind)),
        _field(context, 'sales.activity_date', item.activityDate),
        _field(context, 'sales.client', item.clientName),
        if (item.projectName.isNotEmpty)
          _field(context, 'sales.project', item.projectName),
        if (item.propertyReference.isNotEmpty)
          _field(context, 'sales.property', item.propertyReference),
        if (item.purpose != null)
          _field(context, 'sales.purpose', item.purpose!),
        if (item.outcome != null)
          _field(context, 'sales.outcome', item.outcome!),
        if (item.followUpDate != null)
          _field(context, 'sales.follow_up', item.followUpDate!),
        if (item.dealReference != null)
          _field(context, 'sales.contract_reference', item.dealReference!),
        if (item.transactionType != null)
          _field(
              context,
              'sales.transaction_type',
              const ['sale', 'lease'].contains(item.transactionType)
                  ? 'sales.transactions.${item.transactionType}'.tr()
                  : item.transactionType!),
        if (item.value != null && item.currency != null)
          _field(context, 'sales.contract_value',
              salesMoney(item.value!, item.currency!)),
        if (item.notes.isNotEmpty) _field(context, 'sales.notes', item.notes),
        _field(context, 'sales.submitted',
            requestTime(item.submittedAt, timezone)),
        _field(context, 'sales.updated', requestTime(item.updatedAt, timezone)),
        if (item.review case final review?) ...[
          SizedBox(height: AppSpacing.lg),
          Text(
              (item.status == 'pending'
                      ? 'sales.previous_review'
                      : 'sales.review')
                  .tr(),
              style: context.textTheme.titleMedium),
          _field(context, 'sales.status', salesStatusLabel(review.status)),
          _field(context, 'sales.review_reason', review.reason),
          _field(context, 'sales.reviewer', review.by),
          _field(context, 'sales.reviewed', requestTime(review.at, timezone)),
        ],
      ]));
  Widget _field(BuildContext context, String label, String value) => Padding(
      padding: EdgeInsets.only(top: AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.tr(),
            style: context.textTheme.labelMedium
                ?.copyWith(color: context.colors.onSurfaceVariant)),
        SizedBox(height: AppSpacing.xs),
        SelectableText(value, style: context.textTheme.bodyLarge),
      ]));
}
