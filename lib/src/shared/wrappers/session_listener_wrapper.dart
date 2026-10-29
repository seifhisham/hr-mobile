import 'package:hodour/src/imports/imports.dart';
import 'package:hodour/src/ui/auth/providers/session_provider.dart';

class SessionListenerWrapper extends ConsumerStatefulWidget {
  const SessionListenerWrapper({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SessionListenerWrapper> createState() =>
      _SessionListenerWrapperState();
}

class _SessionListenerWrapperState extends ConsumerState<SessionListenerWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(sessionProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (previous is SessionUnknown && next is! SessionUnknown) {
        FlutterNativeSplash.remove();
      }
    });
    return widget.child;
  }
}
