import 'package:hrmobile/src/imports/imports.dart';
import 'package:hrmobile/src/ui/auth/providers/session_provider.dart';
import 'package:hrmobile/src/ui/auth/session_screen.dart';
import 'package:hrmobile/src/ui/account/account_screen.dart';
import 'package:hrmobile/src/ui/account/change_password_screen.dart';
import 'package:hrmobile/src/middleware/app_route_observer.dart';
import 'package:hrmobile/src/ui/attendance/attendance_screen.dart';
import '../ui/requests/requests_screen.dart';
import '../ui/requests/new_request_screen.dart';
import '../ui/requests/request_details_screen.dart';
import '../ui/requests/department_reviews_screen.dart';
import '../ui/notifications/notifications_screen.dart';

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
          path: AppRoutes.requests,
          name: 'requests',
          builder: (context, state) => const RequestsScreen()),
      GoRoute(
          path: AppRoutes.newRequest,
          name: 'newRequest',
          builder: (context, state) => NewRequestScreen(
              attendanceId: state.uri.queryParameters['attendanceId'])),
      GoRoute(
          path: AppRoutes.requestDetails,
          name: 'requestDetails',
          builder: (context, state) =>
              RequestDetailsScreen(id: state.pathParameters['id']!)),
      GoRoute(
          path: '/attendance',
          name: 'attendance',
          builder: (context, state) => const AttendanceScreen()),
      GoRoute(
          path: AppRoutes.splash,
          name: 'session',
          builder: (context, state) => const SessionScreen()),
      GoRoute(
          path: AppRoutes.login,
          name: 'login',
          builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: AppRoutes.home,
          name: 'home',
          builder: (context, state) => const HomePage()),
      GoRoute(
          path: AppRoutes.account,
          name: 'account',
          builder: (context, state) => const AccountScreen()),
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
