import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hodour/src/shared/widgets/ui/app/inputs/app_date_picker.dart';
import 'package:hodour/src/shared/widgets/ui/app/inputs/app_time_picker.dart';
import 'package:hodour/src/theme/theme.dart';
import 'package:hodour/src/theme/color_schemes.dart';

void main() {
  testWidgets('dark date and time fields have visible boundaries',
      (tester) async {
    final theme = buildDarkTheme(primaryColorHex: '#0068DC');
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(children: [
            AppDatePicker(onChanged: (_) {}),
            AppTimePicker(onChanged: (_) {}),
          ]),
        ),
      ),
    ));
    for (final type in [AppDatePicker, AppTimePicker]) {
      final field = tester.widget<Container>(find
          .descendant(of: find.byType(type), matching: find.byType(Container))
          .first);
      final border = (field.decoration! as BoxDecoration).border! as Border;
      expect(_contrast(border.top.color, theme.colorScheme.surface),
          greaterThanOrEqualTo(3));
    }
  });

  test('shared theme keeps text contrast in light and dark mode', () {
    for (final theme in [
      buildLightTheme(primaryColorHex: '#2457A7'),
      buildDarkTheme(primaryColorHex: '#2457A7'),
    ]) {
      final colors = theme.colorScheme;
      final brand = theme.extension<AppColorsExtension>()!;
      expect(theme.appBarTheme.backgroundColor, brand.homeBlue);
      expect(theme.appBarTheme.foregroundColor, brand.onHomeBlue);
      expect(theme.appBarTheme.titleTextStyle?.color, brand.onHomeBlue);
      expect(colors.primaryContainer, brand.homeTrack);
      expect(colors.secondaryContainer, brand.homeTrack);
      expect(
          colors.primary,
          theme.brightness == Brightness.light
              ? brand.homeBlue
              : brand.homeProgress);
      for (final pair in [
        (colors.primary, colors.onPrimary),
        (
          theme.extension<AppColorsExtension>()!.homeBlue,
          theme.extension<AppColorsExtension>()!.onHomeBlue
        ),
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

  test('dark surfaces, controls and status colors remain readable', () {
    final theme = buildDarkTheme(primaryColorHex: '#2457A7');
    final colors = theme.colorScheme;
    final brand = theme.extension<AppColorsExtension>()!;
    final surfaces = [
      colors.surface,
      colors.surfaceDim,
      colors.surfaceBright,
      colors.surfaceContainerLowest,
      colors.surfaceContainerLow,
      colors.surfaceContainer,
      colors.surfaceContainerHigh,
      colors.surfaceContainerHighest,
    ];
    for (final surface in surfaces) {
      expect((surface.r - surface.b).abs(), lessThan(0.04),
          reason: 'Dark surfaces should be neutral charcoal');
      for (final foreground in [
        colors.onSurface,
        colors.onSurfaceVariant,
        colors.primary,
        colors.error,
        brand.success,
        brand.warning,
        brand.info,
      ]) {
        expect(_contrast(surface, foreground), greaterThanOrEqualTo(4.5));
      }
    }
    for (final pair in [
      (colors.secondary, colors.onSecondary),
      (colors.tertiary, colors.onTertiary),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
      (colors.error, colors.onError),
      (colors.errorContainer, colors.onErrorContainer),
      (brand.success, brand.onSuccess),
      (brand.successContainer!, brand.onSuccessContainer!),
      (brand.warning, brand.onWarning),
      (brand.warningContainer!, brand.onWarningContainer!),
      (brand.info, brand.onInfo),
      (brand.infoContainer!, brand.onInfoContainer!),
      (
        theme.inputDecorationTheme.fillColor!,
        theme.inputDecorationTheme.labelStyle!.color!
      ),
      (
        theme.inputDecorationTheme.fillColor!,
        theme.inputDecorationTheme.hintStyle!.color!
      ),
      (
        Color.alphaBlend(colors.onInverseSurface.withValues(alpha: 0.12),
            colors.inverseSurface),
        colors.onInverseSurface
      ),
    ]) {
      expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
          reason: '${pair.$1} / ${pair.$2}');
    }
    expect(_contrast(colors.outline, colors.surfaceContainerLow),
        greaterThanOrEqualTo(3));
  });
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}
