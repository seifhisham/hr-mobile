import 'package:flutter_test/flutter_test.dart';
import 'package:hrmobile/src/theme/theme.dart';

void main() {
  test('navy blue theme keeps text contrast in light and dark mode', () {
    for (final theme in [
      buildLightTheme(primaryColorHex: '#2457A7'),
      buildDarkTheme(primaryColorHex: '#2457A7'),
    ]) {
      final colors = theme.colorScheme;
      for (final pair in [
        (colors.primary, colors.onPrimary),
        (colors.primaryContainer, colors.onPrimaryContainer),
        (colors.secondaryContainer, colors.onSecondaryContainer),
        (colors.surface, colors.onSurface),
        (colors.surfaceContainerLow, colors.onSurface),
        (colors.inverseSurface, colors.onInverseSurface),
      ]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        final contrast =
            a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5),
            reason: '${theme.brightness}: ${pair.$1} / ${pair.$2}');
      }
    }
  });
}
