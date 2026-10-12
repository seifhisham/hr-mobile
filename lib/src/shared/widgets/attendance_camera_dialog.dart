import 'dart:async';
import 'package:camera/camera.dart';
import '../../imports/imports.dart';
import '../../ui/auth/providers/session_provider.dart';
import '../helpers/delete_attendance_photo.dart';

class AttendanceCameraDialog extends ConsumerStatefulWidget {
  const AttendanceCameraDialog({super.key, this.createController});
  final Future<CameraController> Function()? createController;

  @override
  ConsumerState<AttendanceCameraDialog> createState() =>
      _AttendanceCameraDialogState();
}

class _AttendanceCameraDialogState extends ConsumerState<AttendanceCameraDialog>
    with WidgetsBindingObserver {
  CameraController? _controller;
  RequestState<void> _capture = const RequestInitial();
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final CameraController controller;
      if (widget.createController case final create?) {
        controller = await create();
      } else {
        final cameras = await availableCameras();
        if (cameras.isEmpty) throw CameraException('NoCamera', '');
        controller = CameraController(
            cameras
                    .where((camera) =>
                        camera.lensDirection == CameraLensDirection.back)
                    .firstOrNull ??
                cameras.first,
            ResolutionPreset.high,
            enableAudio: false);
      }
      if (!mounted || _closed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.initialize();
      if (!mounted || _closed) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.detached) {
        _finish();
        return;
      }
      setState(() {});
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    final denied = error is CameraException &&
        (error.code.contains('AccessDenied') ||
            error.code.contains('AccessRestricted'));
    _finish(CaptureFailure(
        denied ? 'attendance.camera_denied' : 'attendance.capture_failed',
        recovery:
            denied ? CaptureRecovery.appSettings : CaptureRecovery.retry));
  }

  void _finish([Object? result]) {
    if (!mounted || _closed) return;
    _closeCamera();
    Navigator.of(context).pop(result);
  }

  void _closeCamera() {
    if (!mounted || _closed) return;
    final controller = _controller;
    setState(() {
      _closed = true;
      _controller = null;
    });
    if (controller != null) unawaited(_disposeCamera(controller));
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capture.isLoading ||
        _closed) {
      return;
    }
    setState(() => _capture = const RequestLoading());
    try {
      final photo = await controller.takePicture();
      if (!mounted || _closed) {
        await deleteAttendancePhoto(photo);
        return;
      }
      _finish(photo);
    } catch (error) {
      _fail(error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts may interrupt initialization; backgrounding cancels evidence.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive &&
            (_controller?.value.isInitialized ?? false))) {
      _finish();
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) unawaited(_disposeCamera(controller));
    super.dispose();
  }

  Future<void> _disposeCamera(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (error) {
      AppLogger.warning('Unable to release attendance camera',
          context: {'type': error.runtimeType.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.userOrNull?.id),
        (previous, next) {
      if (previous != null && previous != next) _finish();
    });
    final controller = _controller;
    final ready = controller?.value.isInitialized ?? false;
    return PopScope<Object?>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _closeCamera();
        },
        child: Dialog(
          shape: const RoundedRectangleBorder(borderRadius: AppBorders.xl),
          insetPadding: EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: 480.w,
                maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('attendance.camera_title'.tr(),
                        style: context.textTheme.titleLarge),
                    SizedBox(height: AppSpacing.xs),
                    Text('attendance.camera_hint'.tr(),
                        style: context.textTheme.bodySmall),
                    SizedBox(height: AppSpacing.md),
                    SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.4,
                        child: ClipRRect(
                            borderRadius: AppBorders.card,
                            child: Center(
                                child: ready
                                    ? CameraPreview(controller!)
                                    : const AppCircularProgress()))),
                    SizedBox(height: AppSpacing.md),
                    AppButton(
                        label: 'attendance.take_photo'.tr(),
                        prefixIcon: Icon(Icons.camera_alt_outlined,
                            color: context.colors.onPrimary),
                        isLoading: _capture.isLoading,
                        onPressed: ready ? _takePhoto : null),
                    AppTextButton(
                        label: 'requests.cancel'.tr(), onPressed: _finish),
                  ]),
            ),
          ),
        ));
  }
}
