import '../../../../../imports/imports.dart';

/// A selectable / deletable chip with Material and Cupertino styling.
///
/// Usage:
/// ```dart
/// AppChip(
///   label: 'Flutter',
///   selected: true,
///   onSelected: (v) => setState(() => selected = v),
///   onDeleted: () => removeTag('Flutter'),
/// )
/// ```
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.avatar,
    this.onDeleted,
    this.platform,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  final VoidCallback? onDeleted;
  final AppPlatformStyle? platform;

  @override
  Widget build(BuildContext context) {
    final useCupertino = platform != null
        ? platform == AppPlatformStyle.cupertino
        : context.isCupertinoUi;
    final cs = context.colors;

    if (!useCupertino) {
      if (onDeleted != null || onSelected == null) {
        return InputChip(
          label: Text(label),
          avatar: avatar,
          selected: selected,
          onSelected: onSelected,
          onDeleted: onDeleted,
          deleteIconColor: cs.onSurfaceVariant,
          selectedColor: cs.secondaryContainer,
          checkmarkColor: cs.onSecondaryContainer,
          shape: const RoundedRectangleBorder(borderRadius: AppBorders.full),
        );
      }

      return FilterChip(
        label: Text(label),
        avatar: avatar,
        selected: selected,
        onSelected: onSelected,
        selectedColor: cs.secondaryContainer,
        checkmarkColor: cs.onSecondaryContainer,
        shape: const RoundedRectangleBorder(borderRadius: AppBorders.full),
      );
    }

    final bg = selected ? cs.secondaryContainer : cs.surfaceContainerHighest;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;

    return GestureDetector(
      onTap: onSelected == null ? null : () => onSelected!(!selected),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.decelerate,
        padding: EdgeInsets.only(
          left: avatar != null ? AppSpacing.xs : AppSpacing.md,
          right: onDeleted != null ? AppSpacing.xs : AppSpacing.md,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppBorders.full,
          border: Border.all(
            color: selected ? cs.secondary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[
              SizedBox(
                width: 24.w,
                height: 24.h,
                child: ClipOval(child: avatar),
              ),
              SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w500,
                fontSize: 13.sp,
              ),
            ),
            if (onDeleted != null) ...[
              SizedBox(width: AppSpacing.xs),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.square(28.w),
                onPressed: onDeleted,
                child: Icon(
                  CupertinoIcons.clear_circled_solid,
                  size: 18.sp,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
