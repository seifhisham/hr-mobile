import 'package:hodour/src/imports/imports.dart';
import '../auth/providers/session_provider.dart';
import 'sales_provider.dart';

/// Access is loaded for every validated session, including review-only managers.
class SalesRefresh extends ConsumerStatefulWidget {
  const SalesRefresh({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SalesRefresh> createState() => _SalesRefreshState();
}

class _SalesRefreshState extends ConsumerState<SalesRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(sessionProvider).userOrNull != null) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final owner = ref.read(sessionProvider).userOrNull?.sessionIdentity;
    await ref.read(salesAccessProvider.notifier).refresh();
    if (!mounted ||
        ref.read(sessionProvider).userOrNull?.sessionIdentity != owner) {
      return;
    }
    ref.read(salesListProvider(false).notifier).refresh();
    if (accessValue(ref.read(salesAccessProvider)).canReview) {
      ref.read(salesListProvider(true).notifier).refresh();
    }
    ref.invalidate(salesDetailProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(salesAccessProvider);
    return widget.child;
  }
}
