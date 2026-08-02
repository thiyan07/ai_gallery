import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_gallery/core/di/providers.dart' as di_providers;
import 'package:ai_gallery/core/theme/theme_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Theme Persistence Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test(
      'ThemeModeNotifier defaults to system and loads from SharedPreferences',
      () async {
        // 1. Setup mock storage with pre-existing value
        await prefs.setString('settings_theme_mode', 'dark');

        final container = ProviderContainer(
          overrides: [di_providers.sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        // 2. Read the provider value
        final themeMode = container.read(themeModeProvider);
        expect(themeMode, ThemeMode.dark);
      },
    );

    test('ThemeModeNotifier saves changes to SharedPreferences', () async {
      final container = ProviderContainer(
        overrides: [di_providers.sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);

      // Change the theme
      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.light);

      // Verify state changes and stores
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(prefs.getString('settings_theme_mode'), 'light');
    });

    test('AccentColorNotifier loads and saves custom color seed', () async {
      const customColor = Colors.orange;
      await prefs.setInt('settings_accent_color', customColor.toARGB32());

      final container = ProviderContainer(
        overrides: [di_providers.sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      // Verify loads correct color
      expect(
        container.read(accentColorProvider).toARGB32(),
        customColor.toARGB32(),
      );

      // Set new color
      const newColor = Colors.teal;
      await container
          .read(accentColorProvider.notifier)
          .setAccentColor(newColor);

      // Verify update
      expect(
        container.read(accentColorProvider).toARGB32(),
        newColor.toARGB32(),
      );
      expect(prefs.getInt('settings_accent_color'), newColor.toARGB32());
    });
  });
}
