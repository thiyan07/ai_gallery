import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_providers.dart';

// Telemetry Notifier
class TelemetryNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.watch(storageServiceProvider).isTelemetryEnabled();
  }

  Future<void> toggle(bool val) async {
    state = val;
    await ref.read(storageServiceProvider).setTelemetryEnabled(val);
  }
}

final telemetryEnabledProvider = NotifierProvider<TelemetryNotifier, bool>(TelemetryNotifier.new);

// Cloud Backup Notifier
class CloudBackupNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.watch(storageServiceProvider).isCloudBackupEnabled();
  }

  Future<void> setEnabled(bool val) async {
    state = val;
    await ref.read(storageServiceProvider).setCloudBackupEnabled(val);
  }
}

final cloudBackupEnabledProvider = NotifierProvider<CloudBackupNotifier, bool>(CloudBackupNotifier.new);

// Sync Wifi Only Notifier
class SyncWifiOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.watch(storageServiceProvider).isSyncWifiOnly();
  }

  Future<void> toggle(bool val) async {
    state = val;
    await ref.read(storageServiceProvider).setSyncWifiOnly(val);
  }
}

final syncWifiOnlyProvider = NotifierProvider<SyncWifiOnlyNotifier, bool>(SyncWifiOnlyNotifier.new);

// Sync Frequency Notifier
class SyncFrequencyNotifier extends Notifier<String> {
  @override
  String build() {
    return ref.watch(storageServiceProvider).getSyncFrequency();
  }

  Future<void> setFrequency(String val) async {
    state = val;
    await ref.read(storageServiceProvider).setSyncFrequency(val);
  }
}

final syncFrequencyProvider = NotifierProvider<SyncFrequencyNotifier, String>(SyncFrequencyNotifier.new);

// API Provider Key configuration modes
// Modes: 'local' (Local Only), 'hybrid' (Hybrid), 'byok' (Bring Your Own Key)
class ApiKeysModeNotifier extends Notifier<String> {
  @override
  String build() {
    final storage = ref.watch(storageServiceProvider);
    // Dynamic derivation or default
    return 'local';
  }

  Future<void> setMode(String mode) async {
    state = mode;
  }
}

final apiKeysModeProvider = NotifierProvider<ApiKeysModeNotifier, String>(ApiKeysModeNotifier.new);
