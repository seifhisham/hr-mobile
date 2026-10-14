import 'dart:math' as math;
import '../../../../../imports/imports.dart';

/// A single destination in [AppBottomNavBar].
class AppBottomNavItem {
  const AppBottomNavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

/// Adaptive bottom navigation bar.
///
/// Usage:
/// ```dart
/// AppBottomNavBar(
///   currentIndex: index,
///   onTap: (i) => setState(() => index = i),
///   items: const [
///     AppBottomNavItem(label: 'Home', icon: Icons.home_outlined),
///     AppBottomNavItem(label: 'Profile', icon: Icons.person_outline),
///   ],
/// )
/// ```
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.platform,
    this.featuredIndex,
  });

  final List<AppBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final AppPlatformStyle? platform;
  final int? featuredIndex;

  @override
  Widget build(BuildContext context) {
    final useCupertino = platform != null
        ? platform == AppPlatformStyle.cupertino
        : context.isCupertinoUi;
    final colors = context.colors;

    if (useCupertino) {
      return CupertinoTabBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: colors.surfaceContainer,
        activeColor: colors.primary,
        inactiveColor: colors.onSurfaceVariant,
        items: [
          for (final item in items)
            BottomNavigationBarItem(
              icon: Icon(item.icon),
              activeIcon: Icon(item.activeIcon ?? item.icon),
              label: item.label,
            ),
        ],
      );
    }

    final featured = featuredIndex;
    final remaining = [
      for (var i = 0; i < items.length; i++)
        if (i != featured) i,
    ];
    final split = (remaining.length + 1) ~/ 2;
    final diameter = AppSpacing.xxl
        .clamp(kMinInteractiveDimension, double.infinity)
        .toDouble();
    final lift = AppSpacing.md;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: featured == null ? 0 : lift),
            child: ClipRRect(
              borderRadius: AppBorders.xl,
              child: ClipPath(
                clipper: featured == null
                    ? null
                    : _DockNotchClipper(
                        diameter: diameter, lift: lift, gap: AppSpacing.xs),
                child: Material(
                  color: colors.inverseSurface,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xs),
                    child: featured == null
                        ? _group(context, remaining)
                        : Row(children: [
                            Expanded(
                                child: _group(context, remaining.take(split))),
                            SizedBox(width: diameter + AppSpacing.sm * 2),
                            Expanded(
                                child: _group(context, remaining.skip(split))),
                          ]),
                  ),
                ),
              ),
            ),
          ),
          if (featured != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                  child: SizedBox(
                width: diameter,
                height: diameter,
                child: _destination(context, featured, featured: true),
              )),
            ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, Iterable<int> indices) => Row(
        children: [
          for (final i in indices) Expanded(child: _destination(context, i))
        ],
      );

  Widget _destination(BuildContext context, int i, {bool featured = false}) {
    final colors = context.colors;
    final selected = i == currentIndex;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.normal;
    final foreground = colors.onInverseSurface;
    var tapCount = 0;
    return StatefulBuilder(
        builder: (context, setTapState) => Semantics(
              selected: selected,
              button: true,
              label: items[i].label,
              child: Tooltip(
                message: items[i].label,
                excludeFromSemantics: true,
                child: Material(
                  color: colors.inverseSurface,
                  shape: featured
                      ? CircleBorder(
                          side: BorderSide(
                              color: colors.surface, width: AppSpacing.xxs))
                      : null,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    overlayColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.pressed)) {
                        return foreground.withValues(alpha: 0.08);
                      }
                      if (states.contains(WidgetState.focused)) {
                        return foreground.withValues(alpha: 0.12);
                      }
                      if (states.contains(WidgetState.hovered)) {
                        return foreground.withValues(alpha: 0.04);
                      }
                      return Colors.transparent;
                    }),
                    customBorder: featured ? const CircleBorder() : null,
                    borderRadius: AppBorders.card,
                    onTap: () {
                      setTapState(() => tapCount++);
                      onTap(i);
                    },
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.xs,
                            horizontal: AppSpacing.xxs),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TweenAnimationBuilder<double>(
                                key: ValueKey((selected, tapCount)),
                                tween: Tween(begin: 0, end: 1),
                                duration: duration,
                                curve: AppCurves.standard,
                                builder: (context, progress, child) {
                                  final pulse = selected || tapCount > 0
                                      ? math.sin(math.pi * progress)
                                      : 0.0;
                                  return Transform.translate(
                                    offset: Offset(0, -AppSpacing.xs * pulse),
                                    child: Transform.scale(
                                        scale: 1 + 0.08 * pulse, child: child),
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: duration,
                                  curve: AppCurves.standard,
                                  padding: EdgeInsets.all(AppSpacing.xs),
                                  decoration: BoxDecoration(
                                    color: featured
                                        ? colors.inverseSurface
                                        : selected
                                            ? colors.onInverseSurface
                                                .withValues(alpha: 0.12)
                                            : colors.inverseSurface,
                                    borderRadius: AppBorders.card,
                                  ),
                                  child: Icon(
                                      selected
                                          ? items[i].activeIcon ?? items[i].icon
                                          : items[i].icon,
                                      color: foreground),
                                ),
                              ),
                              if (!featured) ...[
                                SizedBox(height: AppSpacing.xs),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(items[i].label,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.textTheme.labelSmall
                                          ?.copyWith(
                                              color: colors.onInverseSurface,
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500)),
                                ),
                              ],
                            ]),
                      ),
                    ),
                  ),
                ),
              ),
            ));
  }
}

class _DockNotchClipper extends CustomClipper<Path> {
  const _DockNotchClipper(
      {required this.diameter, required this.lift, required this.gap});
  final double diameter, lift, gap;

  @override
  Path getClip(Size size) => const CircularNotchedRectangle().getOuterPath(
        Offset.zero & size,
        Rect.fromCircle(
            center: Offset(size.width / 2, diameter / 2 - lift),
            radius: diameter / 2 + gap),
      );

  @override
  bool shouldReclip(_DockNotchClipper oldClipper) =>
      diameter != oldClipper.diameter ||
      lift != oldClipper.lift ||
      gap != oldClipper.gap;
}
