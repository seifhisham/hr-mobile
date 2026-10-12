import '../../../imports/imports.dart';

/// ToastCard widget to display decent and rich looking toast.
class ToastCard extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Color? color;
  final Color? shadowColor;
  final Color? borderColor;
  final void Function()? onTap;

  const ToastCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.color,
    this.shadowColor,
    this.borderColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: color ?? context.theme.dialogTheme.backgroundColor,
            borderRadius: AppBorders.xl,
            border: Border.all(
              color: borderColor ?? context.colors.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: AppSpacing.md,
                spreadRadius: 0,
                offset: Offset.zero,
                color: shadowColor ?? Colors.black.withValues(alpha: 0.05),
              ),
            ],
          ),
          child: Semantics(
            liveRegion: true,
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Row(children: [
                if (leading != null) ...[
                  leading!,
                  SizedBox(width: AppSpacing.md)
                ],
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, if (subtitle != null) subtitle!])),
                if (trailing != null) ...[
                  SizedBox(width: AppSpacing.xs),
                  trailing!
                ],
              ]),
            ),
          ),
        ));
  }
}
