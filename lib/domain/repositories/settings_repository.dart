import '../models/user_settings.dart';

/// Repository for reading and persisting user settings.
abstract class SettingsRepository {
  /// Loads all user settings.
  UserSettings getSettings();

  /// Saves the full settings object.
  Future<void> saveSettings(UserSettings settings);

  /// Updates theme mode ('system', 'light', 'dark').
  Future<void> setThemeMode(String mode);

  /// Updates accent color ARGB value.
  Future<void> setAccentColor(int color);

  /// Marks onboarding as completed.
  Future<void> setOnboardingCompleted(bool completed);

  /// Updates telemetry preference.
  Future<void> setTelemetryEnabled(bool enabled);

  /// Updates cloud backup preference.
  Future<void> setCloudBackupEnabled(bool enabled);

  /// Updates custom storage path.
  Future<void> setStoragePath(String? path);

  /// Updates sync Wi-Fi only preference.
  Future<void> setSyncWifiOnly(bool wifiOnly);

  /// Updates sync frequency.
  Future<void> setSyncFrequency(String frequency);

  /// Updates AI processing mode.
  Future<void> setAiMode(AiMode mode);

  /// Updates gallery grid column count.
  Future<void> setGridSize(int columns);
}
