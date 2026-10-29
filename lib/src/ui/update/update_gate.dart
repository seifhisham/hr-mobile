import 'package:app_version_update/data/models/app_version_result.dart';
import 'package:hodour/src/imports/imports.dart';
import 'update_provider.dart';

class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  RequestState<void> _launchState = const RequestInitial();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      ref.read(updateProvider.notifier).check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openStore(AppVersionResult update) async {
    setState(() => _launchState = const RequestLoading());
    final result = await UrlLauncherService.instance.launch(update.storeUrl!);
    if (!mounted) return;
    setState(() => _launchState =
        result.fold(RequestFailure.new, (_) => const RequestSuccess(null)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateProvider);
    final allowed = switch (state) {
      RequestSuccess(:final data) => data?.canUpdate != true,
      _ => false,
    };
    return Stack(fit: StackFit.expand, children: [
      Offstage(
          offstage: !allowed,
          child: ExcludeFocus(
              excluding: !allowed,
              child: TickerMode(enabled: allowed, child: widget.child))),
      if (!allowed)
        AppScaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg.w),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                      header: true,
                      child: Text(
                          (state.isSuccess
                                  ? 'update.required'
                                  : 'update.checking')
                              .tr(),
                          style: context.textTheme.titleLarge,
                          textAlign: TextAlign.center)),
                  SizedBox(height: AppSpacing.md.h),
                  switch (state) {
                    RequestSuccess(:final data) => Column(children: [
                        Text('update.message'.tr(),
                            textAlign: TextAlign.center),
                        SizedBox(height: AppSpacing.lg.h),
                        AppButton(
                            label: 'update.action'.tr(),
                            isLoading: _launchState.isLoading,
                            onPressed: () => _openStore(data!)),
                        if (_launchState.isFailure)
                          Semantics(
                              liveRegion: true,
                              child: Text('update.open_failed'.tr(),
                                  textAlign: TextAlign.center)),
                      ]),
                    RequestFailure() => Column(children: [
                        Semantics(
                            liveRegion: true,
                            child: Text('update.check_failed'.tr(),
                                textAlign: TextAlign.center)),
                        SizedBox(height: AppSpacing.lg.h),
                        AppButton(
                            label: 'account.retry'.tr(),
                            onPressed: () =>
                                ref.read(updateProvider.notifier).check()),
                      ]),
                    _ => const AppCircularProgress(),
                  },
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
