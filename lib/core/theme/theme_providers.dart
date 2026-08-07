import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../di/providers.dart' as di_providers;
import '../storage/storage_service.dart';

// Theme Mode Notifier and Provider
class ThemeModeNotifier extends Notifier<ThemeMode> {
  late StorageService _storageService;

  @override
  ThemeMode build() {
    _storageService = ref.watch(di_providers.storageServiceProvider);
    return _loadThemeMode();
  }

  ThemeMode _loadThemeMode() {
    final modeString = _storageService.getThemeMode();
    return switch (modeString) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final modeString = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _storageService.setThemeMode(modeString);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// Accent Color Notifier and Provider
class AccentColorNotifier extends Notifier<Color> {
  late StorageService _storageService;

  @override
  Color build() {
    _storageService = ref.watch(di_providers.storageServiceProvider);
    return _loadAccentColor();
  }

  Color _loadAccentColor() {
    final colorVal = _storageService.getAccentColor();
    return Color(colorVal);
  }

  Future<void> setAccentColor(Color color) async {
    state = color;
    await _storageService.setAccentColor(color.toARGB32());
  }
}

final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);
