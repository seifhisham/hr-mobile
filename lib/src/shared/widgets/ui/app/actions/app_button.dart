import '../../../../../imports/imports.dart';

/// A fully themed button supporting all [ButtonVariant]s and [ButtonSize]s.
///
/// Renders Material or Cupertino based on [platform] / [AppPlatformScope].
///
/// Usage:
/// ```dart
/// AppButton(
///   label: 'Save',
///   onPressed: _save,
///   variant: ButtonVariant.primary,
///   height: ButtonSize.large,
///   isLoading: state.isLoading,
/// )
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.color,
    this.textColor,
    this.height = ButtonSize.medium,
    this.width,
    this.isLoading = false,
    this.isFullWidth = false,
    this.prefixIcon,
    this.suffixIcon,
    this.platform,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final Color? color;
  final Color? textColor;
  final ButtonSize height;
  final ButtonSize? width;
  final bool isLoading;
  final bool isFullWidth;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final AppPlatformStyle? platform;

  @override
  Widget build(BuildContext context) {
    final useCupertino = context.resolveCupertinoUi(platform);
    final cs = context.theme.colorScheme;
    final appColors = context.theme.extension<AppColorsExtension>()!;
    final isDisabled = onPressed == null || isLoading;

    final double buttonHeight = switch (height) {
      ButtonSize.small => 36.h,
      ButtonSize.medium => 48.h,
      ButtonSize.large => 56.h,
    };

    final double? buttonWidth = switch (width) {
      ButtonSize.small => 100.w,
      ButtonSize.medium => 150.w,
      ButtonSize.large => 200.w,
      null => null,
    };

    final double horizontalPadding = switch (height) {
      ButtonSize.small => 12.w,
      ButtonSize.medium => 20.w,
      ButtonSize.large => 28.w,
    };

    final double fontSize = switch (height) {
      ButtonSize.small => 12.sp,
      ButtonSize.medium => 14.sp,
      ButtonSize.large => 16.sp,
    };

    final (bg, fg, border) = switch (variant) {
      ButtonVariant.primary => (
          color ?? cs.primary,
          textColor ?? cs.onPrimary,
          null
        ),
      ButtonVariant.secondary => (
          cs.secondaryContainer,
          textColor ?? cs.onSecondaryContainer,
          null,
        ),
      ButtonVariant.outline => (
          Colors.transparent,
          textColor ?? cs.primary,
          BorderSide(color: cs.outline, width: 1.5),
        ),
      ButtonVariant.ghost => (
          Colors.transparent,
          textColor ?? cs.primary,
          null
        ),
      ButtonVariant.danger => (cs.error, textColor ?? cs.onError, null),
      ButtonVariant.success => (
          appColors.success,
          textColor ?? appColors.onSuccess,
          null,
        ),
    };

    final child = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppDurations.fast,
      switchInCurve: AppCurves.decelerate,
      child: isLoading
          ? SizedBox(
              key: const ValueKey('loader'),
              width: 20.w,
              height: 20.h,
              child: useCupertino
                  ? CupertinoActivityIndicator(color: fg)
                  : CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (prefixIcon != null) ...[
                  prefixIcon!,
                  SizedBox(width: 8.w),
                ],
                Flexible(
                    child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: isDisabled ? fg.withValues(alpha: 0.5) : fg,
                  ),
                )),
                if (suffixIcon != null) ...[
                  SizedBox(width: 8.w),
                  suffixIcon!,
                ],
              ],
            ),
    );

    final sized = SizedBox(
      width: isFullWidth ? double.infinity : buttonWidth,
      child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: buttonHeight < kMinInteractiveDimension
                  ? kMinInteractiveDimension
                  : buttonHeight),
          child: useCupertino
              ? CupertinoButton(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  color: variant == ButtonVariant.outline ||
                          variant == ButtonVariant.ghost
                      ? null
                      : bg,
                  borderRadius: AppBorders.button,
                  onPressed: isDisabled ? null : onPressed,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: fg),
                    child: child,
                  ),
                )
              : TextButton(
                  onPressed: isDisabled ? null : onPressed,
                  style: TextButton.styleFrom(
                    backgroundColor: bg,
                    foregroundColor: fg,
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    shape: border != null
                        ? RoundedRectangleBorder(
                            borderRadius: AppBorders.button,
                            side: border,
                          )
                        : const RoundedRectangleBorder(
                            borderRadius: AppBorders.button,
                          ),
                  ),
                  child: child,
                )),
    );

    return AnimatedOpacity(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppDurations.fast,
      opacity: isDisabled ? 0.6 : 1.0,
      child: sized,
    );
  }
}
