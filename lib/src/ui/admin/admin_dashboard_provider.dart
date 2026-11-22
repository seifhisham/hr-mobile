import 'package:hodour/src/imports/imports.dart';
import '../../data/models/admin_dashboard.dart';
import '../../data/models/sales_activity.dart';
import '../../data/repositories/admin_dashboard_repository.dart';
import '../../services/admin_dashboard_service.dart';
import '../auth/providers/session_provider.dart';

/// Number of workdays (ending today) loaded for trends.
const adminDashboardDays = 7;

final adminDashboardRepositoryProvider =
    Provider<AdminDashboardRepository>((ref) => AdminDashboardService.instance);

/// Whether the signed-in account gets the admin dashboard tab.
final isAdminProvider = Provider<bool>((ref) =>
    ref.watch(sessionProvider.select((s) => s.userOrNull?.role == 'admin')));

final adminDashboardProvider = StateNotifierProvider.autoDispose<
    AdminDashboardController, RequestState<AdminDashboard>>((ref) {
  final identity =
      ref.watch(sessionProvider.select((s) => s.userOrNull?.sessionIdentity));
  final today = ref.watch(sessionProvider.select((s) => s.userOrNull?.today));
  final enabled = ref.watch(isAdminProvider);
  return AdminDashboardController(ref.read(adminDashboardRepositoryProvider),
      today: enabled && identity != null ? today : null);
});

class AdminDashboardController
    extends StateNotifier<RequestState<AdminDashboard>> {
  AdminDashboardController(this.repository, {required this.today})
      : super(const RequestInitial()) {
    if (today != null) refresh();
  }

  final AdminDashboardRepository repository;

  /// Company calendar date from the session, or null when not allowed.
  final String? today;
  int _generation = 0;

  Future<void> refresh() async {
    final today = this.today;
    if (today == null) return;
    final generation = ++_generation;
    final previous = state;
    if (previous is! RequestSuccess<AdminDashboard>) {
      state = const RequestLoading();
    }
    final days = workdaysEndingOn(today, adminDashboardDays);
    final (attendance, workforce, pending, sales) = await (
      repository.attendance(days.first, today),
      repository.workforce(),
      repository.pendingRequests(),
      repository.salesPerformance(today.substring(0, 7)),
    ).wait;
    if (!mounted || generation != _generation) return;
    // Attendance and the employee list are required; requests and sales are
    // optional sections that show as unavailable when they fail.
    final required = attendance
        .flatMap((rows) => workforce.map((members) => (rows, members)));
    required.fold((failure) {
      if (previous is RequestSuccess<AdminDashboard>) {
        state = previous;
        showGlobalToast(message: failure.message, status: 'error');
      } else {
        state = RequestFailure(failure);
      }
    },
        (data) => state = RequestSuccess(AdminDashboard(
              today: today,
              days: days,
              attendance: data.$1,
              workforce: data.$2,
              pending: pending.toNullable(),
              sales: sales.fold<List<SalesPerformance>?>(
                  (_) => null, (rows) => rows),
            )));
  }
}

/// [count] calendar dates ending on [today] (`yyyy-MM-dd`), oldest first.
List<String> workdaysEndingOn(String today, int count) {
  final end = DateTime.parse('${today}T00:00:00Z');
  return [
    for (var i = count - 1; i >= 0; i--)
      end.subtract(Duration(days: i)).toIso8601String().substring(0, 10)
  ];
}
