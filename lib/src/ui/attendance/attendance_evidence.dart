import 'package:hodour/src/imports/imports.dart';
import '../../data/models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../auth/providers/session_provider.dart';
import 'attendance_summary.dart' show attendanceTime;

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
    return AlertDialog(
        title: Text('attendance.evidence'.tr()),
        content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
                child: switch (state) {
              RequestInitial() ||
              RequestLoading() =>
                const Center(child: CircularProgressIndicator()),
              RequestFailure(:final failure) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(failure.message),
                  AppButton(
                      label: 'attendance.refresh'.tr(),
                      onPressed: () => ref
                          .read(attendanceEvidenceProvider(record.id).notifier)
                          .load()),
                ]),
              RequestSuccess(:final data) => data.isEmpty
                  ? Text('attendance.no_evidence'.tr())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          for (final item in data) ...[
                            Text(
                                (item.event == 'check-in'
                                        ? 'attendance.check_in'
                                        : 'attendance.check_out')
                                    .tr(),
                                style: context.textTheme.titleMedium),
                            Image.memory(item.photo,
                                semanticLabel: 'attendance.evidence'.tr(),
                                errorBuilder: (_, __, ___) =>
                                    Text('attendance.photo_invalid'.tr())),
                            Text('attendance.captured_at'.tr(namedArgs: {
                              'time': attendanceTime(
                                  item.capturedAt, record.timezone)
                            })),
                            Text('attendance.submitted_at'.tr(namedArgs: {
                              'time': attendanceTime(
                                  item.submittedAt, record.timezone)
                            })),
                            Text('attendance.location'.tr(namedArgs: {
                              'latitude': item.latitude.toStringAsFixed(6),
                              'longitude': item.longitude.toStringAsFixed(6)
                            })),
                            Text('attendance.accuracy_distance'.tr(namedArgs: {
                              'accuracy':
                                  item.accuracyMeters.toStringAsFixed(1),
                              'distance': item.distanceMeters.toStringAsFixed(1)
                            })),
                            Text(record.timezone),
                            SizedBox(height: AppSpacing.md.h),
                          ]
                        ]),
            })),
        actions: [
          AppTextButton(
              label: 'attendance.close'.tr(),
              onPressed: () => Navigator.of(context).pop())
        ]);
  }
}
