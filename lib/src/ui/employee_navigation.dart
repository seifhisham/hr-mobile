import 'package:hrmobile/src/imports/imports.dart';
import '../theme/theme_toggle_button.dart';
import 'notifications/notification_button.dart';
import 'auth/providers/session_provider.dart';

class EmployeeNavigation extends ConsumerWidget {
  const EmployeeNavigation({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasEmployee = ref
        .watch(sessionProvider.select((s) => s.userOrNull?.employee != null));
    return AppBottomNavBar(
      featuredIndex: 0,
      currentIndex: index == 4 && !hasEmployee ? 0 : index,
      onTap: (value) => context.goNamed(
          const ['home', 'attendance', 'requests', 'account', 'sales'][value]),
      items: [
        AppBottomNavItem(
            label: 'home.home_title'.tr(),
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded),
        AppBottomNavItem(
            label: 'attendance.nav_label'.tr(),
            icon: Icons.access_time_rounded,
            activeIcon: Icons.access_time_filled_rounded),
        AppBottomNavItem(
            label: 'requests.title'.tr(),
            icon: Icons.description_outlined,
            activeIcon: Icons.description_rounded),
        AppBottomNavItem(
            label: 'account.title'.tr(),
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded),
        if (hasEmployee)
          AppBottomNavItem(
              label: 'sales.title'.tr(),
              icon: Icons.home_work_outlined,
              activeIcon: Icons.home_work_rounded),
      ],
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
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                          color: context.colors.primaryContainer,
                          borderRadius: AppBorders.lg),
                      child:
                          Icon(icon, color: context.colors.onPrimaryContainer),
                    ))),
            const ThemeToggleButton(),
            const NotificationButton(),
          ]),
          SizedBox(height: AppSpacing.md),
          Text(title, style: context.textTheme.headlineMedium),
          SizedBox(height: AppSpacing.sm),
          Text(subtitle,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
        ]),
      );
}
