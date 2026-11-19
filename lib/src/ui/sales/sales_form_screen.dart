import 'package:hodour/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../auth/providers/session_provider.dart';
import 'sales_provider.dart';
import '../requests/request_detail_widgets.dart'
    show RequestNotice, RequestNoticeTone;
import 'sales_form_widgets.dart';
import 'sales_widgets.dart';

class SalesFormScreen extends ConsumerStatefulWidget {
  const SalesFormScreen({super.key, this.id});
  final String? id;
  @override
  ConsumerState<SalesFormScreen> createState() => _SalesFormScreenState();
}

class _SalesFormScreenState extends ConsumerState<SalesFormScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'clientName',
      'projectName',
      'propertyReference',
      'purpose',
      'outcome',
      'dealReference',
      'value',
      'currency',
      'notes'
    ])
      key: TextEditingController()
  };
  String _kind = 'meeting', _transaction = 'sale', _date = '';
  Object? _owner;
  String? _followUp, _validation;
  SalesActivity? _loaded;
  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).userOrNull;
    _owner = user?.sessionIdentity;
    _date = user?.today ?? '';
    _fields['currency']!.text = 'EGP';
    if (ref.read(salesMutationProvider).pending
        case SalesPendingCreate(:final input) when widget.id == null) {
      _kind = input.kind;
      _date = input.activityDate;
      final payload = input.toJson();
      _transaction = payload['transactionType'] as String? ?? 'sale';
      _followUp = payload['followUpDate'] as String?;
      for (final entry in _fields.entries) {
        entry.value.text = payload[entry.key]?.toString() ?? '';
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(salesMutationProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(SalesActivity item) {
    final input = item.submission.toJson();
    _loaded = item;
    _kind = item.kind;
    _transaction = item.transactionType ?? 'sale';
    _date = item.activityDate;
    _followUp = item.followUpDate;
    for (final entry in _fields.entries) {
      entry.value.text = input[entry.key]?.toString() ?? '';
    }
    _validation = null;
  }

  void _changeKind(String value) {
    setState(() {
      _kind = value;
      for (final key in ['purpose', 'outcome', 'dealReference', 'value']) {
        _fields[key]!.clear();
      }
      _fields['currency']!.text = 'EGP';
      _followUp = null;
      _transaction = 'sale';
      _validation = null;
    });
  }

  SalesSubmission _input() {
    String text(String key) => _fields[key]!.text;
    return _kind == 'closed-deal'
        ? SalesDeal(
            activityDate: _date,
            clientName: text('clientName'),
            projectName: text('projectName'),
            propertyReference: text('propertyReference'),
            notes: text('notes'),
            dealReference: text('dealReference'),
            transactionType: _transaction,
            value: num.tryParse(text('value')) ?? 0,
            currency: text('currency').trim())
        : SalesVisit(
            kind: _kind,
            activityDate: _date,
            clientName: text('clientName'),
            projectName: text('projectName'),
            propertyReference: text('propertyReference'),
            notes: text('notes'),
            purpose: text('purpose'),
            outcome: text('outcome'),
            followUpDate: _followUp);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final user = ref.read(sessionProvider).userOrNull;
    if (user?.sessionIdentity != _owner || user?.employee == null) return;
    final input = _input();
    final error =
        input.validate(startDate: user!.employee!.startDate, today: user.today);
    setState(() => _validation = error);
    if (error != null) return;
    final controller = ref.read(salesMutationProvider.notifier);
    if (_loaded case final item?) {
      await controller.correct(item, input);
    } else {
      await controller.create(input);
    }
    // A recovered POST can navigate with its confirmed ID, never with a guessed one.
    if (!mounted ||
        ref.read(sessionProvider).userOrNull?.sessionIdentity != _owner) {
      return;
    }
    final action = ref.read(salesMutationProvider).action;
    if (action case RequestSuccess(:final data)) {
      context.replaceNamed('salesActivityDetails',
          pathParameters: {'id': data.id});
    }
  }

  Widget _field(String key, String label,
          {bool required = false,
          int max = 120,
          bool money = false,
          bool multiline = false,
          bool enabled = true,
          IconData? icon}) =>
      AppTextField(
          key: ValueKey(key),
          controller: _fields[key],
          enabled: enabled,
          // Only optional fields are flagged; everything else is required.
          label: required ? label.tr() : '${label.tr()} (${'sales.optional'.tr()})',
          hint: key == 'currency' ? 'EGP' : null,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          keyboardType: money
              ? const TextInputType.numberWithOptions(decimal: true)
              : multiline
                  ? TextInputType.multiline
                  : TextInputType.text,
          maxLines: multiline ? 3 : 1,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) {
              return 'sales.errors.required'.tr();
            }
            if (text.length > max) {
              return 'sales.errors.max'.tr(namedArgs: {'max': '$max'});
            }
            if (key == 'value' && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
              return 'sales.errors.money'.tr();
            }
            if (key == 'currency' && !RegExp(r'^[A-Z]{3}$').hasMatch(text)) {
              return 'sales.errors.currency'.tr();
            }
            return null;
          });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).userOrNull;
    final access = accessValue(ref.watch(salesAccessProvider));
    final mutation = ref.watch(salesMutationProvider);
    final detail =
        widget.id == null ? null : ref.watch(salesDetailProvider(widget.id!));
    ref.listen(sessionProvider.select((s) => s.userOrNull?.sessionIdentity),
        (_, next) {
      if (next != _owner) {
        for (final controller in _fields.values) {
          controller.clear();
        }
        _loaded = null;
        _date = '';
        _followUp = null;
      }
    });
    if (user == null || user.sessionIdentity != _owner) {
      return const SizedBox.shrink();
    }
    final item = detail?.value?.fold<SalesActivity?>((_) => null, (r) => r);
    // Fill once after a read; never replace unsaved input during a rebuild.
    if (item != null && _loaded == null && item.supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _loaded == null &&
            ref.read(sessionProvider).userOrNull?.sessionIdentity == _owner) {
          setState(() => _load(item));
        }
      });
    }
    final canEdit = access.canSubmit &&
        user.employee != null &&
        (widget.id == null ||
            (item != null && item.canCorrect(user.employee?.id)));
    final enabled = canEdit &&
        !mutation.action.isLoading &&
        mutation.pending == null &&
        (widget.id == null || _loaded != null);
    final employee = user.employee;
    final deal = _kind == 'closed-deal';
    final gap = SizedBox(height: AppSpacing.md);
    return AppScaffold(
        appBar: AppTopBar(
            title:
                (widget.id == null ? 'sales.register' : 'sales.correct').tr(),
            titleWidget: Text(
                (widget.id == null ? 'sales.register' : 'sales.correct').tr(),
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600))),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Form(
                    key: _form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (detail?.isLoading ?? false)
                            const Center(child: CircularProgressIndicator()),
                          if (detail?.value
                                  ?.fold<Failure?>((f) => f, (_) => null)
                              case final failure?) ...[
                            RequestNotice(
                                message: failure.message,
                                tone: RequestNoticeTone.error),
                            gap,
                            AppButton(
                                label: 'sales.refresh'.tr(),
                                onPressed: () => ref.invalidate(
                                    salesDetailProvider(widget.id!))),
                            gap,
                          ],
                          if (item != null &&
                              _loaded != null &&
                              item.revision != _loaded!.revision) ...[
                            RequestNotice(
                                message: 'sales.changed'.tr(),
                                tone: RequestNoticeTone.warning),
                            SizedBox(height: AppSpacing.sm),
                            AppButton(
                                label: 'sales.reload_activity'.tr(),
                                variant: ButtonVariant.outline,
                                onPressed: mutation.action.isLoading
                                    ? null
                                    : () => setState(() => _load(item))),
                            gap,
                          ],
                          if (!canEdit && !(detail?.isLoading ?? false)) ...[
                            RequestNotice(
                                message: 'sales.correction_unavailable'.tr(),
                                tone: RequestNoticeTone.warning),
                            gap,
                          ],
                          const SalesMutationFeedback(),
                          if (employee != null &&
                              (widget.id == null || _loaded != null)) ...[
                            Semantics(
                                header: true,
                                child: Text('sales.record_heading'.tr(),
                                    style: context.textTheme.titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700))),
                            SizedBox(height: AppSpacing.xs),
                            SalesFieldHint('sales.form_hint'.tr()),
                            gap,
                            SalesKindSelector(
                                value: _kind,
                                enabled: enabled,
                                onChanged: _changeKind),
                            SizedBox(height: AppSpacing.sm),
                            SalesFieldHint(
                                'sales.kind_help.${_kind.replaceAll('-', '_')}'
                                    .tr()),
                            gap,
                            SalesFormSection(
                                title: 'sales.activity_section'.tr(),
                                children: [
                                  _field('clientName', 'sales.client',
                                      required: true,
                                      enabled: enabled,
                                      icon: Icons.person_outline_rounded),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        AppDatePicker(
                                            label: 'sales.activity_date'.tr(),
                                            value: DateTime.tryParse(_date),
                                            enabled: enabled,
                                            firstDate: DateTime.parse(
                                                employee.startDate),
                                            lastDate:
                                                DateTime.parse(user.today),
                                            onChanged: (date) => setState(() {
                                                  _date = salesDate(date);
                                                  if (_followUp != null &&
                                                      _followUp!.compareTo(
                                                              _date) <
                                                          0) {
                                                    _followUp = null;
                                                  }
                                                })),
                                        SizedBox(height: AppSpacing.xs),
                                        SalesFieldHint('sales.date_hint'
                                            .tr(namedArgs: {'date': user.today})),
                                      ]),
                                  _field('propertyReference', 'sales.property',
                                      required: _kind != 'meeting',
                                      enabled: enabled,
                                      icon: Icons.location_on_outlined),
                                  _field('projectName', 'sales.project',
                                      enabled: enabled,
                                      icon: Icons.apartment_outlined),
                                ]),
                            gap,
                            SalesFormSection(
                                title: (deal
                                        ? 'sales.contract_section'
                                        : 'sales.result_section')
                                    .tr(),
                                children: [
                                  if (deal) ...[
                                    _field('dealReference',
                                        'sales.contract_reference',
                                        required: true,
                                        enabled: enabled,
                                        icon: Icons.receipt_long_outlined),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text('sales.transaction_type'.tr(),
                                              style: context
                                                  .textTheme.labelMedium
                                                  ?.copyWith(
                                                      color: context.colors
                                                          .onSurfaceVariant)),
                                          SizedBox(height: AppSpacing.xs),
                                          IgnorePointer(
                                              ignoring: !enabled,
                                              child: AppSegmentedControl<
                                                      String>(
                                                  segments: [
                                                    for (final v in [
                                                      'sale',
                                                      'lease'
                                                    ])
                                                      AppSegment(
                                                          value: v,
                                                          label:
                                                              'sales.transactions.$v'
                                                                  .tr()),
                                                  ],
                                                  value: _transaction,
                                                  onChanged: (v) => setState(
                                                      () => _transaction = v))),
                                        ]),
                                    LayoutBuilder(builder: (context, box) {
                                      final narrow = box.maxWidth < 300 ||
                                          MediaQuery.textScalerOf(context)
                                                  .scale(1) >
                                              1.4;
                                      final value = _field(
                                          'value', 'sales.contract_value',
                                          required: true,
                                          money: true,
                                          max: 20,
                                          enabled: enabled,
                                          icon: Icons.payments_outlined);
                                      final currency = _field(
                                          'currency', 'sales.currency',
                                          required: true,
                                          max: 3,
                                          enabled: enabled);
                                      return narrow
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                  value,
                                                  SizedBox(
                                                      height: AppSpacing.md),
                                                  currency
                                                ])
                                          : Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                  Expanded(
                                                      flex: 2, child: value),
                                                  SizedBox(
                                                      width: AppSpacing.md),
                                                  Expanded(child: currency),
                                                ]);
                                    }),
                                    SalesFieldHint('sales.value_hint'.tr()),
                                  ] else ...[
                                    _field('purpose', 'sales.purpose',
                                        required: true,
                                        enabled: enabled,
                                        icon: Icons.flag_outlined),
                                    _field('outcome', 'sales.outcome',
                                        required: true,
                                        enabled: enabled,
                                        icon: Icons.task_alt_rounded),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          AppDatePicker(
                                              label:
                                                  '${'sales.follow_up'.tr()} (${'sales.optional'.tr()})',
                                              // Empty until chosen, so it never
                                              // looks like a date was picked.
                                              value: _followUp == null
                                                  ? null
                                                  : DateTime.tryParse(
                                                      _followUp!),
                                              hint: 'sales.no_follow_up'.tr(),
                                              firstDate:
                                                  DateTime.tryParse(_date),
                                              lastDate: DateTime(2100, 12, 31),
                                              enabled: enabled,
                                              onChanged: (date) => setState(
                                                  () => _followUp =
                                                      salesDate(date))),
                                          if (_followUp != null)
                                            Align(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: AppTextButton(
                                                    label:
                                                        'sales.clear_follow_up'
                                                            .tr(),
                                                    onPressed: enabled
                                                        ? () => setState(() =>
                                                            _followUp = null)
                                                        : null)),
                                        ]),
                                  ],
                                  _field('notes', 'sales.notes',
                                      max: 1000,
                                      multiline: true,
                                      enabled: enabled,
                                      icon: Icons.notes_rounded),
                                ]),
                            gap,
                            if (_validation != null) ...[
                              Semantics(
                                  liveRegion: true,
                                  child: RequestNotice(
                                      message: _validation!.tr(),
                                      tone: RequestNoticeTone.error)),
                              gap,
                            ],
                            AppButton(
                                label: (widget.id == null
                                        ? 'sales.submit_for_review'
                                        : 'sales.resubmit')
                                    .tr(),
                                isLoading: mutation.action.isLoading,
                                onPressed: enabled &&
                                        (item == null ||
                                            _loaded?.revision == item.revision)
                                    ? _save
                                    : null),
                            if (mutation.action
                                case RequestSuccess(:final data))
                              AppTextButton(
                                  label: 'sales.view_saved'.tr(),
                                  onPressed: () => context.replaceNamed(
                                      'salesActivityDetails',
                                      pathParameters: {'id': data.id})),
                          ],
                        ])))));
  }
}
