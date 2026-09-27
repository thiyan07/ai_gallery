import '../services/model_downloader.dart';
import '../logging/app_logger.dart';

/// Manages ONNX models: downloading, selection, and provider integration.
class ModelManager {
  ModelManager({
    required this.downloader,
    required this.logger,
  });

  final ModelDownloader downloader;
  final AppLogger logger;

  String? _selectedModel;
  ModelConfig? _selectedConfig;

  /// Currently selected model name.
  String? get selectedModel => _selectedModel;

  /// Currently selected model config.
  ModelConfig? get selectedConfig => _selectedConfig;

  /// Set the active model.
  ///
  /// Accepts either the preset key (e.g. `siglip-base-patch16-224`) or the
  /// resolved local name (e.g. `siglip_base_patch16_224`). Previous code
  /// passed `resolvedLocalName` from [LocalModelsScreen] which failed the
  /// map lookup and left [_selectedConfig] null, breaking download-state
  /// tracking and causing the AvailableModels tile to never show progress.
  void selectModel(String modelName) {
    _selectedModel = modelName;
    _selectedConfig = ModelPresets.presets[modelName];
    // Fallback: search by resolvedLocalName if key lookup failed
    _selectedConfig ??= ModelPresets.presets.values
        .where((c) => c.resolvedLocalName == modelName)
        .firstOrNull;
    logger.info('Selected model: $modelName -> ${_selectedConfig?.resolvedLocalName ?? "unknown"}');
  }

  /// Get path to selected model, downloading if needed.
  ///
  /// Returns a [ModelDownloadResult] with state, path, and any error.
  /// If [config] is provided, uses that directly instead of the shared selection.
  Future<ModelDownloadResult> getSelectedModelPath({
    void Function(double)? progressCallback,
    void Function(ModelState)? stateCallback,
    ModelConfig? config,
  }) async {
    final resolved = config ?? _selectedConfig;
    if (resolved == null) {
      return ModelDownloadResult(
        localPath: '',
        state: ModelState.failed,
        errorMessage: 'No model selected',
      );
    }

    // Check if already installed and valid
    if (await downloader.isModelDownloaded(resolved.resolvedLocalName)) {
      logger.info('Model already installed: ${resolved.resolvedLocalName}');
      return ModelDownloadResult(
        localPath: await downloader.getModelPath(resolved.resolvedLocalName),
        state: ModelState.installed,
      );
    }

    // Download the model with full validation
    logger.info('Downloading model: ${resolved.modelId}');
    stateCallback?.call(ModelState.downloading);
    return downloader.downloadModelConfig(
      resolved,
      progressCallback: progressCallback,
      stateCallback: stateCallback,
    );
  }

  /// Get current download state for the selected model.
  ModelState getDownloadState() {
    if (_selectedConfig == null) return ModelState.notInstalled;
    return downloader.getModelState(_selectedConfig!.resolvedLocalName);
  }

  /// Get available preset models.
  List<ModelConfig> getAvailablePresets() {
    return ModelPresets.presets.values.toList();
  }

  /// Get list of downloaded models.
  Future<List<DownloadedModel>> getDownloadedModels() {
    return downloader.listModels();
  }

  /// Delete a model.
  Future<void> deleteModel(String modelName) {
    return downloader.deleteModel(modelName);
  }

  /// Clean up partial downloads.
  Future<void> cleanupPartialDownloads() {
    return downloader.cleanupPartialDownloads();
  }
}