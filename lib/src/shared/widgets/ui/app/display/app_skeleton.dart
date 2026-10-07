import '../../../../../imports/imports.dart';

/// Skeleton / shimmer wrapper around placeholder content.
///
/// When `flags.usesSkeletonizer` is enabled, wraps [child] in [Skeletonizer].
/// Otherwise falls back to a simple shimmering container overlay.
///
/// Usage:
/// ```dart
/// AppSkeleton(
///   enabled: isLoading,
///   child: AppListTile(title: 'Loading…'),
/// )
/// ```
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    required this.child,
    this.enabled = true,
    this.ignorePointers = true,
  });

  final Widget child;
  final bool enabled;
  final bool ignorePointers;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Skeletonizer(
      enabled: enabled,
      ignorePointers: ignorePointers,
      child: child,
    );
  }
}

