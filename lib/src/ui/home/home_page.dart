import 'package:hodour/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import '../attendance/attendance_summary.dart';
import '../attendance/attendance_provider.dart';
import '../attendance/attendance_monitoring.dart';
import '../requests/requests_provider.dart';
import '../sales/sales_provider.dart';
import 'home_header.dart';
import 'home_attention.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.userOrNull;
    if (user == null) return const SizedBox.shrink();
    final salesAccess = user.employee == null
        ? accessValue(ref.watch(salesAccessProvider))
        : null;
    return AppScaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            if (user.employee == null) return;
            await Future.wait([
              ref.read(attendanceProvider.notifier).refresh(),
              ref.read(managedRequestsProvider.notifier).refresh(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
                bottom: AppSpacing.xxxl +
                    AppSpacing.xxl +
                    MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeHeader(
                    user: user,
                    child: user.employee == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                Text('account.no_employee'.tr()),
                                if (salesAccess?.canReview ?? false)
                                  AppTextButton(
                                      label: 'sales.team_title'.tr(),
                                      onPressed: () =>
                                          context.pushNamed('teamSales')),
                              ])
                        : const AttendanceSummary(homeStyle: true)),
                const AttendanceLocationStatus(),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (session
                          case SessionAuthenticated(
                            profileRefresh: RequestFailure(:final failure)
                          ))
                        Text(
                            '${'account.profile_stale'.tr()} ${failure.message}'),
                      if (user.employee != null) const HomeAttention(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
