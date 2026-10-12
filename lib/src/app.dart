import 'package:hrmobile/src/imports/core_imports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/theme_mode_provider.dart';
import 'ui/notifications/notification_refresh.dart';
import 'ui/sales/sales_refresh.dart';
import 'ui/attendance/attendance_monitoring.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget current = _buildMaterialApp(context, ref);
    current = AppPlatformScope(
      style: AppPlatformStyle.material,
      child: current,
    );
    return ScreenUtilWrapper(child: current);
  }

  Widget _buildMaterialApp(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'hrmobile',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(primaryColorHex: '#2457A7'),
      darkTheme: buildDarkTheme(primaryColorHex: '#2457A7'),
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        Widget current = child!;
        current = SkeletonWrapper(child: current);
        current = SessionListenerWrapper(child: current);
        current = NotificationRefresh(child: current);
        current = SalesRefresh(child: current);
        current = AttendanceMonitoring(child: current);
        return current;
      },
    );
  }
}
