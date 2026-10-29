import 'dart:async';
import 'package:hodour/src/imports/imports.dart';
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
        widget.child,
        Positioned.fill(
            child: IgnorePointer(
                child: Padding(
                    padding: EdgeInsets.all(AppSpacing.ms),
                    child: CircularProgressIndicator(
                      value: widget.record.progressAt(_now),
                      strokeWidth: AppSpacing.ms,
                      strokeCap: StrokeCap.round,
                      color: context.appColors.homeProgress,
                      backgroundColor: context.appColors.homeTrack,
                      semanticsLabel:
                          'attendance.elapsed'.tr(namedArgs: {'time': time}),
                    )))),
      ]),
      SizedBox(height: AppSpacing.ms),
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text: time,
              style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          TextSpan(
              text: ' ${'attendance.worked'.tr()}',
              style: context.textTheme.bodyLarge
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
        ]),
        semanticsLabel: 'attendance.elapsed'.tr(namedArgs: {'time': time}),
        textAlign: TextAlign.center,
      ),
    ]);
  }
}
