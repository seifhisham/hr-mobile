/// Centralized route path constants for GoRouter.
///
/// Use these variables instead of raw strings throughout the app.
/// Example: `context.go(AppRoutes.onboarding)` instead of `context.go('/')`.
abstract final class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String account = '/account';
  static const String changePassword = '/account/password';
  static const String requests = '/requests';
  static const String newRequest = '/requests/new';
  static const String requestDetails = '/requests/:id';
  static const String notifications = '/notifications';
  static const String departmentReviews = '/department-reviews';
  static const String managedRequestDetails = '/department-reviews/:id';

  /// Debug-only component gallery.
  static const String uiShowcase = '/debug/ui-showcase';
}
