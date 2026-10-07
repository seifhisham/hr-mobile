import 'package:hrmobile/src/imports/imports.dart';
import 'theme_mode_provider.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themeModeProvider);
    final dark = context.theme.brightness == Brightness.dark;
    return AppIconButton(
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
