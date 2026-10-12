import '../../imports/imports.dart';

void showToast(
  BuildContext context, {
  required String message,
  String? status = 'success',
  dynamic icon,
  Duration? duration,
  bool? autoDismiss,
}) {
  final toastStatus = status ?? 'info';
  final colorScheme = context.colors;
  final appColors = context.appColors;

  final (backgroundColor, foregroundColor, iconColor) = switch (toastStatus) {
    'error' => (
        colorScheme.errorContainer,
        colorScheme.onError,
        colorScheme.error,
      ),
    'success' => (
        appColors.successContainer ?? appColors.success,
        appColors.onSuccess,
        appColors.success,
      ),
    'warning' => (
        appColors.warningContainer ?? appColors.warning,
        appColors.onWarning,
        appColors.warning,
      ),
    'info' => (
        appColors.infoContainer ?? appColors.info,
        appColors.onInfo,
        appColors.info,
      ),
    _ => (
        context.theme.scaffoldBackgroundColor,
        colorScheme.onSurface,
        colorScheme.onSurfaceVariant,
      ),
  };

  late final ToastBar toast;
  toast = ToastBar(
    position: ToastPosition.top,
    autoDismiss: autoDismiss ?? true,
    toastDuration: duration ?? const Duration(seconds: 2),
    animationDuration: const Duration(milliseconds: 150),
    animationCurve: Curves.easeIn,
    builder: (context) => ToastCard(
      color: Color.alphaBlend(
          backgroundColor.withValues(alpha: 0.35), colorScheme.surface),
      borderColor: iconColor.withValues(alpha: 0.25),
      shadowColor: colorScheme.shadow.withValues(alpha: 0.05),
      leading: Container(
        padding: EdgeInsets.all(AppSpacing.sm),
        decoration:
            BoxDecoration(color: iconColor, borderRadius: AppBorders.card),
        child: AppIcon(
          icon: icon ??
              (toastStatus == 'success'
                  ? IconsaxPlusBold.tick_circle
                  : toastStatus == 'error' || toastStatus == 'warning'
                      ? Icons.warning_rounded
                      : IconsaxPlusBold.info_circle),
          color: foregroundColor,
          size: AppSpacing.xl,
        ),
      ),
      trailing: AppIconButton(
          icon: Icons.close_rounded,
          tooltip: 'requests.close'.tr(),
          size: ButtonSize.large,
          color: colorScheme.onSurfaceVariant,
          onPressed: () => toast.remove()),
      title: Text(
        message,
        style: context.textTheme.bodyMedium!.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
    ),
  );
  toast.show(context);
}

void showGlobalToast({
  required String message,
  String? status = 'success',
  dynamic icon,
  Duration? duration,
  bool? autoDismiss,
}) {
  final ctx = rootContext;
  if (ctx == null) return;

  showToast(
    ctx,
    message: message,
    status: status,
    icon: icon,
    duration: duration,
    autoDismiss: autoDismiss,
  );
}
