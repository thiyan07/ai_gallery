import '../../core/storage/storage_service.dart';
import '../../domain/models/user_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// SharedPreferences-backed implementation of [SettingsRepository].
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._storage);

  final StorageService _storage;

  @override
  UserSettings getSettings() {
    return UserSettings(
      themeMode: _storage.getThemeMode(),
      accentColor: _storage.getAccentColor(),
      onboardingCompleted: _storage.isOnboardingCompleted(),
      telemetryEnabled: _storage.isTelemetryEnabled(),
      cloudBackupEnabled: _storage.isCloudBackupEnabled(),
      storagePath: _storage.getStoragePath(),
      syncWifiOnly: _storage.isSyncWifiOnly(),
      syncFrequency: _storage.getSyncFrequency(),
      aiMode: _parseAiMode(_storage.getAiMode()),
      gridSize: _storage.getGridSize(),
    );
  }

  @override
  Future<void> saveSettings(UserSettings settings) async {
    await _storage.setThemeMode(settings.themeMode);
    await _storage.setAccentColor(settings.accentColor);
    await _storage.setOnboardingCompleted(settings.onboardingCompleted);
    await _storage.setTelemetryEnabled(settings.telemetryEnabled);
    await _storage.setCloudBackupEnabled(settings.cloudBackupEnabled);
    if (settings.storagePath != null) {
      await _storage.setStoragePath(settings.storagePath!);
    }
    await _storage.setSyncWifiOnly(settings.syncWifiOnly);
    await _storage.setSyncFrequency(settings.syncFrequency);
    await _storage.setAiMode(settings.aiMode.name);
    await _storage.setGridSize(settings.gridSize);
  }

  @override
  Future<void> setThemeMode(String mode) => _storage.setThemeMode(mode);

  @override
  Future<void> setAccentColor(int color) => _storage.setAccentColor(color);

  @override
  Future<void> setOnboardingCompleted(bool completed) =>
      _storage.setOnboardingCompleted(completed);

  @override
  Future<void> setTelemetryEnabled(bool enabled) =>
      _storage.setTelemetryEnabled(enabled);

  @override
  Future<void> setCloudBackupEnabled(bool enabled) =>
      _storage.setCloudBackupEnabled(enabled);

  @override
  Future<void> setStoragePath(String? path) async {
    if (path != null) {
      await _storage.setStoragePath(path);
    }
  }

  @override
  Future<void> setSyncWifiOnly(bool wifiOnly) =>
      _storage.setSyncWifiOnly(wifiOnly);

  @override
  Future<void> setSyncFrequency(String frequency) =>
      _storage.setSyncFrequency(frequency);

  @override
  Future<void> setAiMode(AiMode mode) => _storage.setAiMode(mode.name);

  @override
  Future<void> setGridSize(int columns) => _storage.setGridSize(columns);

  AiMode _parseAiMode(String value) {
    return AiMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => AiMode.local,
    );
  }
}
