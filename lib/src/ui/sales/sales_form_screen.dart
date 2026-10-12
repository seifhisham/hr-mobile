import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import '../auth/providers/session_provider.dart';
import 'sales_provider.dart';
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
  String _kind = 'meeting', _transaction = 'sale', _date = '', _owner = '';
  String? _followUp, _validation;
  SalesActivity? _loaded;
  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).userOrNull;
    _owner = user?.id ?? '';
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
    if (user?.id != _owner || user?.employee == null) return;
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
    if (!mounted || ref.read(sessionProvider).userOrNull?.id != _owner) return;
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
          bool enabled = true}) =>
      Padding(
          padding: EdgeInsets.only(top: AppSpacing.md),
          child: AppTextField(
              key: ValueKey(key),
              controller: _fields[key],
              enabled: enabled,
              label:
                  '${label.tr()}${required ? ' *' : ' (${'sales.optional'.tr()})'}',
              hint: key == 'currency' ? 'EGP' : null,
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
                if (key == 'value' &&
                    !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
                  return 'sales.errors.money'.tr();
                }
                if (key == 'currency' &&
                    !RegExp(r'^[A-Z]{3}$').hasMatch(text)) {
                  return 'sales.errors.currency'.tr();
                }
                return null;
              }));
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).userOrNull;
    final access = accessValue(ref.watch(salesAccessProvider));
    final mutation = ref.watch(salesMutationProvider);
    final detail =
        widget.id == null ? null : ref.watch(salesDetailProvider(widget.id!));
    ref.listen(sessionProvider.select((s) => s.userOrNull?.id), (_, next) {
      if (next != _owner) {
        for (final controller in _fields.values) {
          controller.clear();
        }
        _loaded = null;
        _date = '';
        _followUp = null;
      }
    });
    if (user == null || user.id != _owner) return const SizedBox.shrink();
    final item = detail?.value?.fold<SalesActivity?>((_) => null, (r) => r);
    // Fill once after a read; never replace unsaved input during a rebuild.
    if (item != null && _loaded == null && item.supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _loaded == null &&
            ref.read(sessionProvider).userOrNull?.id == _owner) {
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
                child: Theme(
                    data: Theme.of(context).copyWith(
                        inputDecorationTheme: Theme.of(context)
                            .inputDecorationTheme
                            .copyWith(
                                labelStyle: context.textTheme.bodyMedium
                                    ?.copyWith(
                                        color:
                                            context.colors.onSurfaceVariant))),
                    child: Form(
                        key: _form,
                        child:
                            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          SalesNotice(text: 'sales.form_hint'.tr()),
                          SizedBox(height: AppSpacing.md),
                          if (detail?.isLoading ?? false)
                            const Center(child: CircularProgressIndicator()),
                          if (detail?.value
                                  ?.fold<Failure?>((f) => f, (_) => null)
                              case final failure?) ...[
                            Text(failure.message,
                                style: TextStyle(color: context.colors.error)),
                            AppButton(
                                label: 'sales.refresh'.tr(),
                                onPressed: () => ref.invalidate(
                                    salesDetailProvider(widget.id!))),
                          ],
                          if (item != null &&
                              _loaded != null &&
                              item.revision != _loaded!.revision) ...[
                            SalesNotice(text: 'sales.changed'.tr()),
                            AppButton(
                                label: 'sales.reload_activity'.tr(),
                                variant: ButtonVariant.outline,
                                onPressed: mutation.action.isLoading
                                    ? null
                                    : () => setState(() => _load(item))),
                          ],
                          if (!canEdit && !(detail?.isLoading ?? false))
                            Text('sales.correction_unavailable'.tr()),
                          const SalesMutationFeedback(),
                          if (employee != null &&
                              (widget.id == null || _loaded != null)) ...[
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  Text('sales.activity_section'.tr(),
                                      style: context.textTheme.titleLarge),
                                  SizedBox(height: AppSpacing.md),
                                  AppDropdown<String>(
                                      label: 'sales.type'.tr(),
                                      value: _kind,
                                      enabled: enabled,
                                      items: [
                                        for (final kind in salesKinds)
                                          AppDropdownItem(
                                              value: kind,
                                              label: salesKindLabel(kind)),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) _changeKind(v);
                                      }),
                                  SizedBox(height: AppSpacing.sm),
                                  Text(
                                      'sales.kind_help.${_kind.replaceAll('-', '_')}'
                                          .tr()),
                                  SizedBox(height: AppSpacing.md),
                                  AppDatePicker(
                                      label: 'sales.activity_date'.tr(),
                                      value: DateTime.tryParse(_date),
                                      enabled: enabled,
                                      firstDate:
                                          DateTime.parse(employee.startDate),
                                      lastDate: DateTime.parse(user.today),
                                      onChanged: (date) => setState(() {
                                            _date = salesDate(date);
                                            if (_followUp != null &&
                                                _followUp!.compareTo(_date) <
                                                    0) {
                                              _followUp = null;
                                            }
                                          })),
                                  Text('sales.date_hint'
                                      .tr(namedArgs: {'date': user.today})),
                                  _field('clientName', 'sales.client',
                                      required: true, enabled: enabled),
                                  _field('projectName', 'sales.project',
                                      enabled: enabled),
                                  _field('propertyReference', 'sales.property',
                                      required: _kind != 'meeting',
                                      enabled: enabled),
                                ])),
                            SizedBox(height: AppSpacing.lg),
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  Text(
                                      (_kind == 'closed-deal'
                                              ? 'sales.contract_section'
                                              : 'sales.result_section')
                                          .tr(),
                                      style: context.textTheme.titleLarge),
                                  if (_kind == 'closed-deal') ...[
                                    _field('dealReference',
                                        'sales.contract_reference',
                                        required: true, enabled: enabled),
                                    SizedBox(height: AppSpacing.md),
                                    AppDropdown<String>(
                                        label: 'sales.transaction_type'.tr(),
                                        value: _transaction,
                                        enabled: enabled,
                                        items: [
                                          for (final v in ['sale', 'lease'])
                                            AppDropdownItem(
                                                value: v,
                                                label: 'sales.transactions.$v'
                                                    .tr()),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            setState(() => _transaction = v);
                                          }
                                        }),
                                    _field('value', 'sales.contract_value',
                                        required: true,
                                        money: true,
                                        max: 20,
                                        enabled: enabled),
                                    _field('currency', 'sales.currency',
                                        required: true,
                                        max: 3,
                                        enabled: enabled),
                                    SizedBox(height: AppSpacing.sm),
                                    Text('sales.value_hint'.tr()),
                                  ] else ...[
                                    _field('purpose', 'sales.purpose',
                                        required: true, enabled: enabled),
                                    _field('outcome', 'sales.outcome',
                                        required: true, enabled: enabled),
                                    SizedBox(height: AppSpacing.md),
                                    AppDatePicker(
                                        label:
                                            '${'sales.follow_up'.tr()} (${'sales.optional'.tr()})',
                                        value: _followUp == null
                                            ? DateTime.tryParse(_date)
                                            : DateTime.tryParse(_followUp!),
                                        firstDate: DateTime.tryParse(_date),
                                        lastDate: DateTime(2100, 12, 31),
                                        enabled: enabled,
                                        onChanged: (date) => setState(
                                            () => _followUp = salesDate(date))),
                                    Text(
                                        _followUp ?? 'sales.no_follow_up'.tr()),
                                    if (_followUp != null)
                                      AppTextButton(
                                          label: 'sales.clear_follow_up'.tr(),
                                          onPressed: enabled
                                              ? () => setState(
                                                  () => _followUp = null)
                                              : null),
                                  ],
                                  _field('notes', 'sales.notes',
                                      max: 1000,
                                      multiline: true,
                                      enabled: enabled),
                                ])),
                            SizedBox(height: AppSpacing.lg),
                            if (_validation != null)
                              Semantics(
                                  liveRegion: true,
                                  child: Text(_validation!.tr(),
                                      style: TextStyle(
                                          color: context.colors.error))),
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
                            SizedBox(height: AppSpacing.sm),
                            Text('sales.required_hint'.tr(),
                                style: context.textTheme.bodySmall),
                            if (mutation.action
                                case RequestSuccess(:final data))
                              AppTextButton(
                                  label: 'sales.view_saved'.tr(),
                                  onPressed: () => context.replaceNamed(
                                      'salesActivityDetails',
                                      pathParameters: {'id': data.id})),
                          ],
                        ]))))));
  }
}
