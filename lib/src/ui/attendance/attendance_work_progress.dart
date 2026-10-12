import 'dart:async';
import 'package:hrmobile/src/imports/imports.dart';
import '../../data/models/attendance_model.dart';

/// Updates elapsed work locally; the saved check-in remains the source of truth.
class AttendanceWorkProgress extends StatefulWidget {
  const AttendanceWorkProgress(
      {super.key, required this.record, required this.child});
  final AttendanceRecord record;
  final Widget child;

  @override
  State<AttendanceWorkProgress> createState() => _AttendanceWorkProgressState();
}

class _AttendanceWorkProgressState extends State<AttendanceWorkProgress>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.record.elapsedAt(_now);
    final time = [
      elapsed.inHours,
      elapsed.inMinutes % 60,
      elapsed.inSeconds % 60
    ].map((part) => part.toString().padLeft(2, '0')).join(':');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(alignment: Alignment.center, children: [
        Padding(padding: EdgeInsets.all(AppSpacing.sm), child: widget.child),
        Positioned.fill(
            child: IgnorePointer(
                child: CircularProgressIndicator(
          value: widget.record.progressAt(_now),
          strokeWidth: AppSpacing.sm,
          strokeCap: StrokeCap.round,
          color: context.colors.primary,
          backgroundColor: context.colors.primaryContainer,
          semanticsLabel: 'attendance.elapsed'.tr(namedArgs: {'time': time}),
        ))),
      ]),
      SizedBox(height: AppSpacing.sm),
      Text('attendance.elapsed'.tr(namedArgs: {'time': time}),
          textAlign: TextAlign.center, style: context.textTheme.titleSmall),
    ]);
  }
}
