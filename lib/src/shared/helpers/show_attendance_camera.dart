import 'package:camera/camera.dart';
import '../../imports/imports.dart';
import '../widgets/attendance_camera_dialog.dart';

Future<XFile?> showAttendanceCamera() async {
  if (rootContext == null) {
    throw const CaptureFailure('attendance.capture_failed');
  }
  final result = await showAppDialog<Object>(
    child: const AttendanceCameraDialog(),
    hasBlur: false,
    duration: MediaQuery.disableAnimationsOf(rootContext!)
        ? Duration.zero
        : AppDurations.normal,
  );
  return switch (result) {
    final XFile photo => photo,
    final CaptureFailure failure => throw failure,
    _ => null,
  };
}
