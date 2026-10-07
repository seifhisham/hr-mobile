import 'package:hrmobile/src/imports/imports.dart';
import '../theme/theme_toggle_button.dart';
import 'notifications/notification_button.dart';

class EmployeeNavigation extends StatelessWidget {
  const EmployeeNavigation({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => AppBottomNavBar(
        currentIndex: index,
        onTap: (value) => context.goNamed(
            const ['home', 'attendance', 'requests', 'account'][value]),
        items: [
          AppBottomNavItem(
              label: 'home.home_title'.tr(), icon: Icons.home_outlined),
          AppBottomNavItem(
              label: 'attendance.title'.tr(), icon: Icons.access_time_rounded),
          AppBottomNavItem(
              label: 'requests.title'.tr(), icon: Icons.description_outlined),
          AppBottomNavItem(
              label: 'account.title'.tr(), icon: Icons.person_outline_rounded),
        ],
      );
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
