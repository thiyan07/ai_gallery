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

  /// Currently selected model name.
  String? get selectedModel => _selectedModel;

  /// Set the active model.
  void selectModel(String modelName) {
    _selectedModel = modelName;
    logger.info('Selected model: $modelName');
  }

  /// Get path to selected model, downloading if needed.
  Future<String?> getSelectedModelPath({
    void Function(double)? progressCallback,
  }) async {
    if (_selectedModel == null) return null;

    final config = ModelPresets.presets[_selectedModel!];
    if (config == null) return null;

    if (await downloader.isModelDownloaded(config.localName)) {
      return await downloader.getModelPath(config.localName);
    }

    // Download the model
    logger.info('Downloading model: ${config.modelId}');
    return downloader.downloadModel(
      modelId: config.modelId,
      filename: config.filename,
      progressCallback: progressCallback,
    );
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
}