import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static const String _keyThemeMode = 'settings_theme_mode';
  static const String _keyAccentColor = 'settings_accent_color';
  static const String _keyOnboardingCompleted = 'settings_onboarding_completed';
  static const String _keyTelemetryEnabled = 'settings_telemetry_enabled';
  static const String _keyCloudBackupEnabled = 'settings_cloud_backup_enabled';
  static const String _keyStoragePath = 'settings_storage_path';
  static const String _keySyncWifiOnly = 'settings_sync_wifi_only';
  static const String _keySyncFrequency = 'settings_sync_frequency';

  // Theme Mode: 'system', 'light', 'dark'
  String getThemeMode() => _prefs.getString(_keyThemeMode) ?? 'system';
  Future<bool> setThemeMode(String value) => _prefs.setString(_keyThemeMode, value);

  // Accent Color: ARGB value (int)
  int getAccentColor() => _prefs.getInt(_keyAccentColor) ?? 0xFF6200EE; // Default purple
  Future<bool> setAccentColor(int value) => _prefs.setInt(_keyAccentColor, value);

  // Onboarding
  bool isOnboardingCompleted() => _prefs.getBool(_keyOnboardingCompleted) ?? false;
  Future<bool> setOnboardingCompleted(bool value) => _prefs.setBool(_keyOnboardingCompleted, value);

  // Telemetry
  bool isTelemetryEnabled() => _prefs.getBool(_keyTelemetryEnabled) ?? false;
  Future<bool> setTelemetryEnabled(bool value) => _prefs.setBool(_keyTelemetryEnabled, value);

  // Cloud Sync
  bool isCloudBackupEnabled() => _prefs.getBool(_keyCloudBackupEnabled) ?? false;
  Future<bool> setCloudBackupEnabled(bool value) => _prefs.setBool(_keyCloudBackupEnabled, value);

  // Storage Path
  String? getStoragePath() => _prefs.getString(_keyStoragePath);
  Future<bool> setStoragePath(String value) => _prefs.setString(_keyStoragePath, value);

  // Sync Configuration
  bool isSyncWifiOnly() => _prefs.getBool(_keySyncWifiOnly) ?? true;
  Future<bool> setSyncWifiOnly(bool value) => _prefs.setBool(_keySyncWifiOnly, value);

  String getSyncFrequency() => _prefs.getString(_keySyncFrequency) ?? 'daily';
  Future<bool> setSyncFrequency(String value) => _prefs.setString(_keySyncFrequency, value);

  // Helper method to clear all preferences (for debugging or settings reset)
  Future<bool> clearAll() => _prefs.clear();
}
