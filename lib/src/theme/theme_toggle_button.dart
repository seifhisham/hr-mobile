import 'package:hodour/src/imports/imports.dart';
import 'theme_mode_provider.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themeModeProvider);
    final dark = context.theme.brightness == Brightness.dark;
    return AppIconButton(
      color: color,
      icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tooltip: (dark ? 'design.light_mode' : 'design.dark_mode').tr(),
      onPressed: preference.isLoading
          ? null
          : () async {
              final result =
                  await ref.read(themeModeProvider.notifier).setDark(!dark);
              result.fold(
                  (failure) => showGlobalToast(message: failure.message),
                  (_) {});
            },
    );
  }
}
