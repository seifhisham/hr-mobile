import 'package:hodour/src/imports/imports.dart';
import '../../data/models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../auth/providers/session_provider.dart';
import 'attendance_record_widgets.dart' show attendanceTime;

final attendanceEvidenceServiceProvider =
    Provider((ref) => AttendanceService.instance);
final attendanceEvidenceProvider = StateNotifierProvider.autoDispose.family<
    AttendanceEvidenceController,
    RequestState<List<AttendanceEvidence>>,
    String>((ref, id) {
  final userId =
      ref.watch(sessionProvider.select((s) => s.userOrNull?.sessionIdentity));
  return AttendanceEvidenceController(
      ref.read(attendanceEvidenceServiceProvider), id,
      enabled: userId != null);
});

class AttendanceEvidenceController
    extends StateNotifier<RequestState<List<AttendanceEvidence>>> {
  AttendanceEvidenceController(this.service, this.id, {bool enabled = true})
      : super(const RequestInitial()) {
    if (enabled) load();
  }
  final AttendanceService service;
  final String id;
  List<AttendanceEvidence> _evidence = [];
  void _clear() {
    for (final item in _evidence) {
      MemoryImage(item.photo).evict();
    }
    _evidence = [];
  }

  Future<void> load() async {
    _clear();
    state = const RequestLoading();
    final result = await service.loadEvidence(id);
    if (!mounted) return;
    state = result.fold((failure) => RequestFailure(failure), (items) {
      _evidence = items;
      return RequestSuccess(items);
    });
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }
}

class AttendanceEvidenceDialog extends ConsumerWidget {
  const AttendanceEvidenceDialog({super.key, required this.record});
  final AttendanceRecord record;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(attendanceEvidenceProvider(record.id));
    if (ref.watch(
            sessionProvider.select((s) => s.userOrNull?.sessionIdentity)) ==
        null) {
      return const SizedBox.shrink();
    }
    return Dialog(
      insetPadding: EdgeInsets.all(AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppSpacing.xxxl * 10,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
                start: AppSpacing.lg,
                end: AppSpacing.sm,
                top: AppSpacing.sm,
                bottom: AppSpacing.sm),
            child: Row(children: [
              Expanded(
                  child: Text('attendance.evidence'.tr(),
                      style: context.textTheme.titleLarge)),
              AppIconButton(
                  icon: Icons.close_rounded,
                  size: ButtonSize.large,
                  tooltip: 'attendance.close'.tr(),
                  onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
              child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: switch (state) {
              RequestInitial() ||
              RequestLoading() =>
                const Center(child: AppCircularProgress()),
              RequestFailure(:final failure) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(failure.message),
                  SizedBox(height: AppSpacing.md),
                  AppButton(
                      label: 'attendance.refresh'.tr(),
                      onPressed: () => ref
                          .read(attendanceEvidenceProvider(record.id).notifier)
                          .load()),
                ]),
              RequestSuccess(:final data) => data.isEmpty
                  ? Text('attendance.no_evidence'.tr())
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final item in data)
                        _EvidenceItem(item: item, timezone: record.timezone),
                    ]),
            },
          )),
        ]),
      ),
    );
  }
}

class _EvidenceItem extends StatelessWidget {
  const _EvidenceItem({required this.item, required this.timezone});
  final AttendanceEvidence item;
  final String timezone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.lg),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(
                item.event == 'check-in'
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                size: AppSpacing.ml,
                color: context.colors.primary),
            SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(
                    (item.event == 'check-in'
                            ? 'attendance.check_in'
                            : 'attendance.check_out')
                        .tr(),
                    style: context.textTheme.titleMedium)),
          ]),
          SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.md),
            child: ColoredBox(
                color: context.colors.surfaceContainerHighest,
                child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Image.memory(item.photo,
                            fit: BoxFit.contain,
                            semanticLabel: 'attendance.evidence'.tr(),
                            errorBuilder: (_, __, ___) => Center(
                                child:
                                    Text('attendance.photo_invalid'.tr())))))),
          ),
          SizedBox(height: AppSpacing.md),
          _detail(context, Icons.schedule_rounded, [
            'attendance.captured_at'.tr(
                namedArgs: {'time': attendanceTime(item.capturedAt, timezone)}),
            'attendance.submitted_at'.tr(namedArgs: {
              'time': attendanceTime(item.submittedAt, timezone)
            }),
            timezone,
          ]),
          SizedBox(height: AppSpacing.sm),
          _detail(context, Icons.location_on_outlined, [
            'attendance.location'.tr(namedArgs: {
              'latitude': item.latitude.toStringAsFixed(6),
              'longitude': item.longitude.toStringAsFixed(6)
            }),
            'attendance.accuracy_distance'.tr(namedArgs: {
              'accuracy': item.accuracyMeters.toStringAsFixed(1),
              'distance': item.distanceMeters.toStringAsFixed(1)
            }),
          ]),
        ]),
      );

  Widget _detail(BuildContext context, IconData icon, List<String> lines) =>
      DecoratedBox(
        decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.md)),
        child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(
                  child: Icon(icon,
                      size: AppSpacing.ml,
                      color: context.colors.onSurfaceVariant)),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    for (var index = 0; index < lines.length; index++)
                      Padding(
                          padding: EdgeInsets.only(
                              top: index == 0 ? 0 : AppSpacing.xs),
                          child: Text(lines[index],
                              style: index == 0
                                  ? context.textTheme.bodyMedium
                                  : context.textTheme.bodySmall?.copyWith(
                                      color: context.colors.onSurfaceVariant))),
                  ])),
            ])),
      );
}
