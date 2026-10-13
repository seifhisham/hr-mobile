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
  const SalesSectionHeading(
      {super.key, required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Semantics(
      header: true,
      child: Row(children: [
        ExcludeSemantics(child: Icon(icon, color: context.colors.primary)),
        SizedBox(width: AppSpacing.sm),
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
            SalesSectionHeading(
                title: row.employeeName, icon: Icons.badge_outlined),
            Text('${row.employeeNumber} · ${row.department}'),
            SizedBox(height: AppSpacing.md),
          ],
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SalesSectionHeading(
                    title: 'sales.verified_results'.tr(),
                    icon: Icons.verified_outlined),
                SizedBox(height: AppSpacing.xs),
                Text('sales.verified_results_hint'.tr(),
                    style: context.textTheme.bodyMedium),
                SizedBox(height: AppSpacing.md),
                _metricGroup(context, 'sales.meeting_total', row.meetingTotal,
                    Icons.groups_outlined, [
                  ('sales.meetings', row.meetings, Icons.groups_outlined),
                  ('sales.viewings', row.viewings, Icons.home_work_outlined),
                ]),
                SizedBox(height: AppSpacing.md),
                _metricGroup(context, 'sales.deals', row.deals,
                    Icons.handshake_outlined, [
                  ('sales.sales_count', row.sales, Icons.sell_outlined),
                  ('sales.leases_count', row.leases, Icons.key_outlined),
                ]),
                SizedBox(height: AppSpacing.lg),
                SalesSectionHeading(
                    title: 'sales.contract_totals'.tr(),
                    icon: Icons.payments_outlined),
                SizedBox(height: AppSpacing.sm),
                if (row.transactionValues.isEmpty)
                  Text('sales.no_verified_contracts'.tr()),
                for (final entry in row.transactionValues.entries)
                  Padding(
                      padding: EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(salesMoney(entry.value, entry.key),
                          style: context.textTheme.titleLarge)),
              ])),
          SizedBox(height: AppSpacing.md),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SalesSectionHeading(
                    title: 'sales.not_counted'.tr(),
                    icon: Icons.pending_actions_outlined),
                SizedBox(height: AppSpacing.md),
                _reviewRow(context, 'pending', row.pending,
                    team ? 'sales.pending_team_hint' : 'sales.pending_hint'),
                SizedBox(height: AppSpacing.md),
                const AppDivider(),
                SizedBox(height: AppSpacing.md),
                _reviewRow(
                    context, 'returned', row.returned, 'sales.returned_hint'),
              ])),
          SizedBox(height: AppSpacing.md),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SalesSectionHeading(
                    title: 'sales.monthly_targets'.tr(),
                    icon: Icons.flag_outlined),
                SizedBox(height: AppSpacing.xs),
                Text('sales.targets_short_hint'.tr(),
                    style: context.textTheme.bodyMedium),
                SizedBox(height: AppSpacing.md),
                if (row.target == null)
                  Text('sales.target_not_set'.tr())
                else ...[
                  _target(
                      context,
                      'sales.meeting_total',
                      Icons.groups_outlined,
                      row.meetingTotal,
                      row.target?.meetings,
                      row.achievement['meetings']),
                  const AppDivider(),
                  _target(context, 'sales.deals', Icons.handshake_outlined,
                      row.deals, row.target?.deals, row.achievement['deals']),
                  const AppDivider(),
                  _target(
                      context,
                      'sales.contract_value',
                      Icons.payments_outlined,
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

  Widget _metricGroup(BuildContext context, String label, int total,
          IconData icon, List<(String, int, IconData)> details) =>
      Container(
        padding: EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
            color: context.colors.surfaceContainerHighest,
            borderRadius: AppBorders.lg),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SalesIconTile(icon: icon),
            SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(label.tr(), style: context.textTheme.titleMedium)),
            SizedBox(width: AppSpacing.sm),
            Text('$total',
                style: context.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          SizedBox(height: AppSpacing.md),
          for (final detail in details)
            Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(children: [
                  ExcludeSemantics(
                      child: Icon(detail.$3,
                          size: AppSpacing.ml,
                          color: context.colors.onSurfaceVariant)),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(detail.$1.tr(),
                          style: context.textTheme.bodyMedium)),
                  SizedBox(width: AppSpacing.sm),
                  Text('${detail.$2}', style: context.textTheme.titleMedium),
                ])),
        ]),
      );

  Widget _reviewRow(
          BuildContext context, String status, int count, String hint) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                SalesStatus(status: status),
                SizedBox(height: AppSpacing.sm),
                Text(hint.tr(), style: context.textTheme.bodyMedium),
              ])),
          SizedBox(width: AppSpacing.md),
          Text('$count',
              style: context.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      );

  Widget _target(BuildContext context, String label, IconData icon, num actual,
          num? target, num? percentage,
          {String? currency}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SalesSectionHeading(title: label.tr(), icon: icon),
          SizedBox(height: AppSpacing.sm),
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
            if (currency != null) ...[
              SizedBox(height: AppSpacing.xs),
              Text(
                  'sales.target_currency_hint'
                      .tr(namedArgs: {'currency': currency}),
                  style: context.textTheme.bodySmall),
            ],
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
          SalesIconTile(icon: salesKindIcon(item.kind)),
          SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(salesKindLabel(item.kind),
                    style: context.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: AppSpacing.xs),
                Text(item.clientName, style: context.textTheme.bodyMedium),
              ])),
          Icon(Directionality.of(context) == TextDirection.rtl
              ? Icons.chevron_left
              : Icons.chevron_right),
        ]),
        SizedBox(height: AppSpacing.sm),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: SalesStatus(status: item.status)),
        SizedBox(height: AppSpacing.sm),
        _metadata(context, Icons.calendar_today_outlined, item.activityDate),
        if (team)
          _metadata(context, Icons.person_outline,
              '${item.employeeName} · ${item.department}'),
        if (item.propertyReference.isNotEmpty)
          _metadata(
              context, Icons.location_on_outlined, item.propertyReference),
        if (item.value != null && item.currency != null)
          _metadata(context, Icons.payments_outlined,
              salesMoney(item.value!, item.currency!)),
      ]));
  Widget _metadata(BuildContext context, IconData icon, String text) => Padding(
        padding: EdgeInsets.only(top: AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
              child: Icon(icon,
                  size: AppSpacing.ml, color: context.colors.onSurfaceVariant)),
          SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(text,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant))),
        ]),
      );
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
