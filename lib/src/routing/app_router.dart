import 'package:hodour/src/imports/imports.dart';
import 'package:hodour/src/ui/auth/providers/session_provider.dart';
import 'package:hodour/src/ui/auth/session_screen.dart';
import 'package:hodour/src/ui/account/account_screen.dart';
import 'package:hodour/src/ui/account/change_password_screen.dart';
import 'package:hodour/src/middleware/app_route_observer.dart';
import 'package:hodour/src/ui/attendance/attendance_screen.dart';
import '../ui/requests/requests_screen.dart';
import '../ui/requests/new_request_screen.dart';
import '../ui/requests/request_details_screen.dart';
import '../ui/requests/department_reviews_screen.dart';
import '../ui/notifications/notifications_screen.dart';
import '../ui/sales/sales_screen.dart';
import '../ui/sales/sales_form_screen.dart';
import '../ui/sales/sales_details_screen.dart';
import '../ui/employee_navigation.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    observers: <NavigatorObserver>[AppRouteObserver()],
    redirect: (context, route) {
      final path = route.matchedLocation;
      return switch (ref.read(sessionProvider)) {
        SessionUnknown() ||
        SessionUnavailable() =>
          path == AppRoutes.splash ? null : AppRoutes.splash,
        SessionUnauthenticated() =>
          path == AppRoutes.login ? null : AppRoutes.login,
        SessionAuthenticated() => path == AppRoutes.login ||
                path == AppRoutes.splash ||
                path == AppRoutes.onboarding
            ? AppRoutes.home
            : null,
      };
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppScaffold(
          extendBody: true,
          bottomNavigationBar: EmployeeNavigation(
              index: switch (state.uri.path) {
            '/attendance' => 1,
            AppRoutes.requests => 2,
            AppRoutes.account => 3,
            AppRoutes.sales => 4,
            _ => 0,
          }),
          body: child,
        ),
        routes: [
          GoRoute(
              path: AppRoutes.home,
              name: 'home',
              pageBuilder: (context, state) =>
                  _workspacePage(state, const HomePage())),
          GoRoute(
              path: '/attendance',
              name: 'attendance',
              pageBuilder: (context, state) =>
                  _workspacePage(state, const AttendanceScreen())),
          GoRoute(
              path: AppRoutes.requests,
              name: 'requests',
              pageBuilder: (context, state) =>
                  _workspacePage(state, const RequestsScreen())),
          GoRoute(
              path: AppRoutes.account,
              name: 'account',
              pageBuilder: (context, state) =>
                  _workspacePage(state, const AccountScreen())),
          GoRoute(
              path: AppRoutes.sales,
              name: 'sales',
              pageBuilder: (context, state) =>
                  _workspacePage(state, const SalesScreen())),
        ],
      ),
      GoRoute(
          path: AppRoutes.teamSales,
          name: 'teamSales',
          builder: (_, state) => const SalesScreen(team: true)),
      GoRoute(
          path: AppRoutes.newSalesActivity,
          name: 'newSalesActivity',
          builder: (_, state) => const SalesFormScreen()),
      GoRoute(
          path: AppRoutes.salesActivityDetails,
          name: 'salesActivityDetails',
          builder: (_, state) => SalesDetailsScreen(
              id: state.pathParameters['id']!,
              team: state.uri.queryParameters['team'] == 'true')),
      GoRoute(
          path: AppRoutes.editSalesActivity,
          name: 'editSalesActivity',
          builder: (_, state) =>
              SalesFormScreen(id: state.pathParameters['id']!)),
      GoRoute(
          path: AppRoutes.notifications,
          name: 'notifications',
          builder: (context, state) => const NotificationsScreen()),
      GoRoute(
          path: AppRoutes.departmentReviews,
          name: 'departmentReviews',
          builder: (context, state) => const DepartmentReviewsScreen()),
      GoRoute(
          path: AppRoutes.managedRequestDetails,
          name: 'managedRequestDetails',
          builder: (context, state) => RequestDetailsScreen(
              id: state.pathParameters['id']!, managed: true)),
      GoRoute(
          path: AppRoutes.newRequest,
          name: 'newRequest',
          builder: (context, state) => NewRequestScreen(
              initialType: state.uri.queryParameters['type'],
              attendanceId: state.uri.queryParameters['attendanceId'])),
      GoRoute(
          path: AppRoutes.requestDetails,
          name: 'requestDetails',
          builder: (context, state) =>
              RequestDetailsScreen(id: state.pathParameters['id']!)),
      GoRoute(
          path: AppRoutes.splash,
          name: 'session',
          builder: (context, state) => const SessionScreen()),
      GoRoute(
          path: AppRoutes.login,
          name: 'login',
          builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: AppRoutes.changePassword,
          name: 'changePassword',
          builder: (context, state) => const ChangePasswordScreen()),
      // Preserve template deep links while directing employees to supported access.
      GoRoute(
          path: AppRoutes.onboarding,
          redirect: (context, state) => AppRoutes.login),
      GoRoute(path: '/signup', redirect: (context, state) => AppRoutes.login),
      GoRoute(
          path: '/forgot-password',
          redirect: (context, state) => AppRoutes.login),
      if (kDebugMode)
        GoRoute(
            path: AppRoutes.uiShowcase,
            name: 'uiShowcase',
            builder: (context, state) => const UiShowcaseScreen()),
    ],
  );
  ref.listen(sessionProvider, (context, state) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

CustomTransitionPage<void> _workspacePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppDurations.medium,
      reverseTransitionDuration: AppDurations.normal,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = animation.drive(CurveTween(curve: AppCurves.smooth));
        return FadeTransition(
          opacity: curved.drive(Tween<double>(begin: 0.85, end: 1)),
          child: child,
        );
      },
    );
