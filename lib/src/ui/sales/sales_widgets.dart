import 'package:hodour/src/imports/imports.dart';
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
      'viewing' => Icons.apartment_outlined,
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
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (status) {
      'verified' => (
          context.appColors.successContainer ?? context.colors.primaryContainer,
          context.appColors.onSuccessContainer ??
              context.colors.onPrimaryContainer,
          Icons.check_circle_outline
        ),
      'returned' => (
          context.colors.errorContainer,
          context.colors.onErrorContainer,
          Icons.edit_note_rounded
        ),
      _ => (
          context.colors.secondaryContainer,
          context.colors.onSecondaryContainer,
          Icons.schedule_outlined
        ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: background, borderRadius: AppBorders.lg),
      child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          children: [
            ExcludeSemantics(
                child: Icon(icon, color: foreground, size: AppSpacing.ml)),
            Text(salesStatusLabel(status),
                style:
                    context.textTheme.labelLarge?.copyWith(color: foreground)),
          ]),
    );
  }
}

class SalesSectionHeading extends StatelessWidget {
  const SalesSectionHeading({super.key, required this.title, this.icon});
  final String title;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
      header: true,
      child: Row(children: [
        if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, color: context.colors.primary)),
          SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
            child: Text(title,
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600))),
      ]));
}

class SalesIconTile extends StatelessWidget {
  const SalesIconTile({super.key, required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
          child: Container(
        padding: EdgeInsets.all(AppSpacing.ms),
        decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            borderRadius: AppBorders.lg),
        child: Icon(icon, color: context.colors.onPrimaryContainer),
      ));
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (team) ...[
            SalesSectionHeading(title: row.employeeName),
            SizedBox(height: AppSpacing.xxs),
            Text('${row.employeeNumber} · ${row.department}',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant)),
            SizedBox(height: AppSpacing.md),
          ],
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SalesSectionHeading(title: 'sales.verified_results'.tr()),
                SizedBox(height: AppSpacing.md),
                _total(context, 'sales.meeting_total', row.meetingTotal, [
                  ('sales.meetings', row.meetings),
                  ('sales.viewings', row.viewings),
                ]),
                SizedBox(height: AppSpacing.sm),
                const AppDivider(),
                SizedBox(height: AppSpacing.sm),
                _total(context, 'sales.deals', row.deals, [
                  ('sales.sales_count', row.sales),
                  ('sales.leases_count', row.leases),
                ]),
                SizedBox(height: AppSpacing.sm),
                const AppDivider(),
                SizedBox(height: AppSpacing.md),
                Text('sales.contract_totals'.tr(),
                    style: context.textTheme.labelMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
                if (row.transactionValues.isEmpty)
                  Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs),
                      child: Text('sales.no_verified_contracts'.tr(),
                          style: context.textTheme.bodyMedium)),
                for (final entry in row.transactionValues.entries)
                  Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(salesMoney(entry.value, entry.key),
                          style: context.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700))),
              ])),
          SizedBox(height: AppSpacing.md),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SalesSectionHeading(title: 'sales.not_counted'.tr()),
                SizedBox(height: AppSpacing.md),
                _reviewRow(context, 'pending', row.pending),
                SizedBox(height: AppSpacing.sm),
                const AppDivider(),
                SizedBox(height: AppSpacing.sm),
                _reviewRow(context, 'returned', row.returned),
              ])),
          SizedBox(height: AppSpacing.md),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SalesSectionHeading(title: 'sales.monthly_targets'.tr()),
                SizedBox(height: AppSpacing.sm),
                if (row.target == null)
                  Text('sales.target_not_set'.tr(),
                      style: context.textTheme.bodyMedium)
                else ...[
                  _target(context, 'sales.meeting_total', row.meetingTotal,
                      row.target?.meetings, row.achievement['meetings']),
                  const AppDivider(),
                  _target(context, 'sales.deals', row.deals, row.target?.deals,
                      row.achievement['deals']),
                  const AppDivider(),
                  _target(
                      context,
                      'sales.contract_value',
                      row.target == null
                          ? 0
                          : row.transactionValues[row.target!.currency] ?? 0,
                      row.target?.transactionValue,
                      row.achievement['transactionValue'],
                      currency: row.target?.currency),
                ],
              ])),
        ],
      );

  /// A total with its parts listed quietly underneath.
  Widget _total(BuildContext context, String label, int total,
          List<(String, int)> parts) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(label.tr(),
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
          SizedBox(width: AppSpacing.sm),
          Text('$total',
              style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: context.colors.primary)),
        ]),
        for (final part in parts)
          Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Row(children: [
                Expanded(
                    child: Text(part.$1.tr(),
                        style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant))),
                SizedBox(width: AppSpacing.sm),
                Text('${part.$2}', style: context.textTheme.bodyMedium),
              ])),
      ]);

  Widget _reviewRow(BuildContext context, String status, int count) => Row(
        children: [
          Expanded(
              child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SalesStatus(status: status))),
          SizedBox(width: AppSpacing.md),
          Text('$count',
              style: context.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      );

  Widget _target(BuildContext context, String label, num actual, num? target,
          num? percentage,
          {String? currency}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label.tr(),
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: AppSpacing.xs),
          if (target == null)
            Text('sales.target_not_set'.tr(),
                style: context.textTheme.bodyMedium)
          else ...[
            Text(
                'sales.target_progress'.tr(namedArgs: {
                  'actual': currency == null
                      ? '$actual'
                      : salesMoney(actual, currency),
                  'target': currency == null
                      ? '$target'
                      : salesMoney(target, currency),
                }),
                style: context.textTheme.bodyMedium),
            if (currency != null)
              Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(
                      'sales.target_currency_hint'
                          .tr(namedArgs: {'currency': currency}),
                      style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant))),
            SizedBox(height: AppSpacing.sm),
            if (percentage != null) ...[
              Text(
                  'sales.target_achieved'.tr(
                      namedArgs: {'percent': percentage.toStringAsFixed(1)}),
                  style: context.textTheme.labelLarge
                      ?.copyWith(color: context.colors.primary)),
              SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                  value: (percentage / 100).clamp(0, 1),
                  semanticsLabel: label.tr(),
                  semanticsValue: percentage.clamp(0, 100).toString()),
            ] else
              Text('sales.unavailable'.tr()),
          ],
        ]),
      );
}

/// One activity in the history list: who/what/when on top, status and
/// value below, with a single quiet line for the property or employee.
class SalesActivityCard extends StatelessWidget {
  const SalesActivityCard(
      {super.key, required this.item, this.team = false, required this.onTap});
  final SalesActivity item;
  final bool team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.onSurfaceVariant;
    final detail = [
      if (team) '${item.employeeName} · ${item.department}',
      if (item.propertyReference.isNotEmpty) item.propertyReference,
    ].join(' · ');
    return AppCard(
        onTap: onTap,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SalesIconTile(icon: salesKindIcon(item.kind)),
            SizedBox(width: AppSpacing.md),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.clientName,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  SizedBox(height: AppSpacing.xxs),
                  Text('${salesKindLabel(item.kind)} · ${item.activityDate}',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: muted)),
                ])),
            Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                color: muted),
          ]),
          SizedBox(height: AppSpacing.md),
          Row(children: [
            Flexible(child: SalesStatus(status: item.status)),
            if (item.value != null && item.currency != null) ...[
              SizedBox(width: AppSpacing.md),
              Expanded(
                  child: Text(salesMoney(item.value!, item.currency!),
                      textAlign: TextAlign.end,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ]),
          if (detail.isNotEmpty) ...[
            SizedBox(height: AppSpacing.sm),
            Text(detail,
                style: context.textTheme.bodySmall?.copyWith(color: muted)),
          ],
        ]));
  }
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
