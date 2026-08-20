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
  void selectModel(String modelName) {
    _selectedModel = modelName;
    _selectedConfig = ModelPresets.presets[modelName];
    logger.info('Selected model: $modelName');
  }

  /// Get path to selected model, downloading if needed.
  ///
  /// Returns a [ModelDownloadResult] with state, path, and any error.
  Future<ModelDownloadResult> getSelectedModelPath({
    void Function(double)? progressCallback,
    void Function(ModelState)? stateCallback,
  }) async {
    if (_selectedConfig == null) {
      return ModelDownloadResult(
        localPath: '',
        state: ModelState.failed,
        errorMessage: 'No model selected',
      );
    }

    final config = _selectedConfig!;

    // Check if already installed and valid
    if (await downloader.isModelDownloaded(config.resolvedLocalName)) {
      logger.info('Model already installed: ${config.resolvedLocalName}');
      return ModelDownloadResult(
        localPath: await downloader.getModelPath(config.resolvedLocalName),
        state: ModelState.installed,
      );
    }

    // Download the model with full validation
    logger.info('Downloading model: ${config.modelId}');
    stateCallback?.call(ModelState.downloading);
    return downloader.downloadModelConfig(
      config,
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