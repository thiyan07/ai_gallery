import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../di/providers.dart' as di_providers;
import '../storage/storage_service.dart';
import '../storage/secure_storage_service.dart';

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
    switch (modeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      case ThemeMode.system:
      default:
        modeString = 'system';
        break;
    }
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
