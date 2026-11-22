import 'package:hodour/src/imports/imports.dart';
import '../theme/theme_toggle_button.dart';
import 'notifications/notification_button.dart';
import 'auth/providers/session_provider.dart';
import 'admin/admin_dashboard_provider.dart';

/// Bottom navigation for the workspace shell. Tabs depend on the account:
/// admins get the company dashboard, employees with a profile get sales.
class EmployeeNavigation extends ConsumerWidget {
  const EmployeeNavigation({super.key, required this.location});

  /// Current shell path, used to highlight the active tab.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasEmployee = ref
        .watch(sessionProvider.select((s) => s.userOrNull?.employee != null));
    final isAdmin = ref.watch(isAdminProvider);
    final tabs = <(String, String, AppBottomNavItem)>[
      (
        'home',
        AppRoutes.home,
        AppBottomNavItem(
            label: 'home.home_title'.tr(),
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded)
      ),
      (
        'attendance',
        AppRoutes.attendance,
        AppBottomNavItem(
            label: 'attendance.nav_label'.tr(),
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month_rounded)
      ),
      (
        'requests',
        AppRoutes.requests,
        AppBottomNavItem(
            label: 'requests.title'.tr(),
            icon: Icons.description_outlined,
            activeIcon: Icons.description_rounded)
      ),
      if (isAdmin)
        (
          'adminDashboard',
          AppRoutes.adminDashboard,
          AppBottomNavItem(
              label: 'admin.nav_label'.tr(),
              icon: Icons.insights_outlined,
              activeIcon: Icons.insights_rounded)
        ),
      (
        'account',
        AppRoutes.account,
        AppBottomNavItem(
            label: 'account.title'.tr(),
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded)
      ),
      if (hasEmployee)
        (
          'sales',
          AppRoutes.sales,
          AppBottomNavItem(
              label: 'sales.title'.tr(),
              icon: Icons.trending_up_rounded,
              activeIcon: Icons.trending_up_rounded)
        ),
    ];
    final current = tabs.indexWhere((tab) => tab.$2 == location);
    return AppBottomNavBar(
      featuredIndex: 0,
      currentIndex: current < 0 ? 0 : current,
      onTap: (value) => context.goNamed(tabs[value].$1),
      items: [for (final tab in tabs) tab.$3],
    );
  }
}

class EmployeeHeading extends StatelessWidget {
  const EmployeeHeading(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon});
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(bottom: AppSpacing.lg),
        padding: EdgeInsets.all(AppSpacing.ml),
        decoration: BoxDecoration(
            color: context.appColors.homeBlue, borderRadius: AppBorders.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                          color: context.appColors.homeTrack,
                          borderRadius: AppBorders.lg),
                      child:
                          Icon(icon, color: context.colors.onPrimaryContainer),
                    ))),
            ThemeToggleButton(color: context.appColors.onHomeBlue),
            NotificationButton(
                color: context.appColors.onHomeBlue, dotBadge: true),
          ]),
          SizedBox(height: AppSpacing.md),
          Semantics(
              header: true,
              child: Text(title,
                  style: context.textTheme.headlineMedium?.copyWith(
                      color: context.appColors.onHomeBlue,
                      fontWeight: FontWeight.w600))),
          SizedBox(height: AppSpacing.sm),
          Text(subtitle,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.appColors.onHomeBlue)),
        ]),
      );
}
