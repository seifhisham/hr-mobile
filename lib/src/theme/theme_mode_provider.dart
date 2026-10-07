import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/utils.dart';

final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
    ThemeModeController.new);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  static const preferenceKey = 'appearance.dark_mode';

  @override
  Future<ThemeMode> build() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getBool(preferenceKey)) {
      true => ThemeMode.dark,
      false => ThemeMode.light,
      null => ThemeMode.system,
    };
  }

  FutureEither<void> setDark(bool dark) => runTask(() async {
        // Finish restoration before saving a new choice.
        await future;
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setBool(preferenceKey, dark)) {
          throw StateError('Unable to save appearance preference');
        }
        if (ref.mounted) {
          state = AsyncData(dark ? ThemeMode.dark : ThemeMode.light);
        }
      }, operation: 'appearance.save', category: LogCategory.database);
}
