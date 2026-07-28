import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/core/theme/theme_providers.dart';
import 'package:ai_gallery/core/di/providers.dart' as di_providers;
import 'package:ai_gallery/core/services/model_downloader.dart';

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
    // Dynamic derivation or default
    return 'local';
  }

  Future<void> setMode(String mode) async {
    state = mode;
  }
}

final apiKeysModeProvider = NotifierProvider<ApiKeysModeNotifier, String>(ApiKeysModeNotifier.new);

// Model Management Notifiers
class ModelManagementNotifier extends Notifier<ModelManagementState> {
  @override
  ModelManagementState build() {
    return ModelManagementState.initial();
  }

  Future<void> loadModels() async {
    state = state.copyWith(isLoading: true);
    try {
      final modelManager = ref.read(di_providers.modelManagerProvider);
      final downloaded = await modelManager.getDownloadedModels();
      final available = modelManager.getAvailablePresets();

      state = state.copyWith(
        downloadedModels: downloaded,
        availablePresets: available,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> downloadModel(ModelConfig preset) async {
    state = state.copyWith(downloadingModel: preset.localName, downloadProgress: 0.0);
    try {
      final modelManager = ref.read(di_providers.modelManagerProvider);
      modelManager.selectModel(preset.modelId.replaceAll('/', '_'));

      await modelManager.getSelectedModelPath(progressCallback: (progress) {
        state = state.copyWith(downloadProgress: progress);
      });

      // Reload models after download
      await loadModels();
    } catch (e) {
      state = state.copyWith(downloadingModel: null, error: e.toString());
    }
  }

  Future<void> deleteModel(String modelName) async {
    state = state.copyWith(isDeleting: true);
    try {
      final modelManager = ref.read(di_providers.modelManagerProvider);
      await modelManager.deleteModel(modelName);
      await loadModels();
    } catch (e) {
      state = state.copyWith(isDeleting: false, error: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

class ModelManagementState {
  const ModelManagementState({
    this.downloadedModels = const [],
    this.availablePresets = const [],
    this.isLoading = false,
    this.downloadingModel,
    this.downloadProgress = 0.0,
    this.isDeleting = false,
    this.error,
  });

  final List<DownloadedModel> downloadedModels;
  final List<ModelConfig> availablePresets;
  final bool isLoading;
  final String? downloadingModel;
  final double downloadProgress;
  final bool isDeleting;
  final String? error;

  factory ModelManagementState.initial() => const ModelManagementState();

  ModelManagementState copyWith({
    List<DownloadedModel>? downloadedModels,
    List<ModelConfig>? availablePresets,
    bool? isLoading,
    String? downloadingModel,
    double? downloadProgress,
    bool? isDeleting,
    String? error,
  }) {
    return ModelManagementState(
      downloadedModels: downloadedModels ?? this.downloadedModels,
      availablePresets: availablePresets ?? this.availablePresets,
      isLoading: isLoading ?? this.isLoading,
      downloadingModel: downloadingModel ?? this.downloadingModel,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isDeleting: isDeleting ?? this.isDeleting,
      error: error,
    );
  }
}

final modelManagementProvider =
    NotifierProvider<ModelManagementNotifier, ModelManagementState>(ModelManagementNotifier.new);

// Current selected model preset
class SelectedModelPresetNotifier extends Notifier<String> {
  @override
  String build() {
    final modelManager = ref.watch(di_providers.modelManagerProvider);
    return modelManager.selectedModel ?? '';
  }

  Future<void> selectModel(String modelId) async {
    final modelManager = ref.read(di_providers.modelManagerProvider);
    modelManager.selectModel(modelId);
    state = modelId;
    ref.read(modelManagementProvider.notifier).loadModels();
  }
}

final selectedModelPresetProvider = NotifierProvider<SelectedModelPresetNotifier, String>(SelectedModelPresetNotifier.new);
