/// AI processing mode for the application.
enum AiMode {
  /// Process everything on-device only.
  local,

  /// On-device first, cloud fallback when needed.
  hybrid,

  /// User provides their own cloud API keys.
  byok,
}

/// Domain model representing persisted user preferences.
class UserSettings {
  /// Theme mode: 'system', 'light', or 'dark'.
  final String themeMode;

  /// Accent color as ARGB integer.
  final int accentColor;

  /// Whether onboarding has been completed.
  final bool onboardingCompleted;

  /// Whether anonymous telemetry is enabled.
  final bool telemetryEnabled;

  /// Whether cloud backup is enabled.
  final bool cloudBackupEnabled;

  /// Custom local storage path, if set.
  final String? storagePath;

  /// Sync only over Wi-Fi when true.
  final bool syncWifiOnly;

  /// Sync frequency: 'daily', 'weekly', etc.
  final String syncFrequency;

  /// AI processing mode.
  final AiMode aiMode;

  /// Gallery grid column count.
  final int gridSize;

  const UserSettings({
    this.themeMode = 'system',
    this.accentColor = 0xFF6200EE,
    this.onboardingCompleted = false,
    this.telemetryEnabled = false,
    this.cloudBackupEnabled = false,
    this.storagePath,
    this.syncWifiOnly = true,
    this.syncFrequency = 'daily',
    this.aiMode = AiMode.local,
    this.gridSize = 3,
  });

  UserSettings copyWith({
    String? themeMode,
    int? accentColor,
    bool? onboardingCompleted,
    bool? telemetryEnabled,
    bool? cloudBackupEnabled,
    String? storagePath,
    bool? syncWifiOnly,
    String? syncFrequency,
    AiMode? aiMode,
    int? gridSize,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
      cloudBackupEnabled: cloudBackupEnabled ?? this.cloudBackupEnabled,
      storagePath: storagePath ?? this.storagePath,
      syncWifiOnly: syncWifiOnly ?? this.syncWifiOnly,
      syncFrequency: syncFrequency ?? this.syncFrequency,
      aiMode: aiMode ?? this.aiMode,
      gridSize: gridSize ?? this.gridSize,
    );
  }
}
