import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/core/di/providers.dart' as di_providers;
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/utils/device_capabilities.dart';

/// Screen for managing local embedding models.
class LocalModelsScreen extends ConsumerStatefulWidget {
  const LocalModelsScreen({super.key});

  @override
  ConsumerState<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends ConsumerState<LocalModelsScreen> {
  late Stream<List<DownloadedModel>> _downloadedModelsStream;

  @override
  void initState() {
    super.initState();
    _downloadedModelsStream = _watchDownloadedModels();
  }

  Stream<List<DownloadedModel>> _watchDownloadedModels() async* {
    final modelManager = ref.read(di_providers.modelManagerProvider);
    while (true) {
      yield await modelManager.getDownloadedModels();
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelManager = ref.watch(di_providers.modelManagerProvider);
    final logger = ref.watch(di_providers.appLoggerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Models'),
      ),
      body: StreamBuilder<List<DownloadedModel>>(
        stream: _downloadedModelsStream,
        builder: (context, downloadedSnapshot) {
          final downloadedModels = downloadedSnapshot.data ?? <DownloadedModel>[];
          final availablePresets = modelManager.getAvailablePresets();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header info
              _buildInfoCard(theme, downloadedModels.length, availablePresets.length),
              const SizedBox(height: 16),

              // Device-specific model recommendation
              _buildDeviceRecommendationCard(theme, downloadedSnapshot, modelManager, logger),
              const SizedBox(height: 24),

              // Installed Models Section
              _buildSectionHeader(theme, 'Installed Models'),
              const SizedBox(height: 8),
              if (downloadedModels.isEmpty)
                _buildEmptyInstalled(theme)
              else
                ...downloadedModels.map((model) => _buildInstalledModelTile(
                      theme,
                      model,
                      modelManager,
                      logger,
                    )),

              const SizedBox(height: 24),

              // Available Models Section
              _buildSectionHeader(theme, 'Available Models'),
              const SizedBox(height: 8),
              ...availablePresets.map((preset) => _buildAvailableModelTile(
                    theme,
                    preset,
                    downloadedModels,
                    modelManager,
                    logger,
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, int installedCount, int availableCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Local models run entirely on your device. No internet required after download.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatChip(
                    theme,
                    '$installedCount',
                    'Installed',
                    Icons.check_circle_outline,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatChip(
                    theme,
                    '$availableCount',
                    'Available',
                    Icons.cloud_download,
                    theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a card showing the recommended model for this device.
  Widget _buildDeviceRecommendationCard(
    ThemeData theme,
    AsyncSnapshot<List<DownloadedModel>> downloadedSnapshot,
    ModelManager modelManager,
    AppLogger logger,
  ) {
    return FutureBuilder<DeviceCapabilities>(
      future: DeviceCapabilities.instance,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final capabilities = snapshot.data!;
        final isRecommendedInstalled = downloadedSnapshot.data?.any(
              (m) => m.name == capabilities.recommendedModelPreset,
            ) ??
            false;

        final recommendedPreset = ModelPresets.presets[capabilities.recommendedModelPreset];

        return Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.smartphone,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended for your device',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            '${capabilities.modelName} (${capabilities.tier.name})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isRecommendedInstalled)
                      Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 24,
                      )
                    else
                      FilledButton.icon(
                        onPressed: () {
                          if (recommendedPreset != null) {
                            _downloadModel(recommendedPreset, modelManager, logger);
                          }
                        },
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Install'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildDetailChip(
                      theme,
                      'Model: ${_getModelDisplayName(capabilities.recommendedModelPreset)}',
                      Icons.model_training,
                    ),
                    _buildDetailChip(
                      theme,
                      '${capabilities.recommendedModelPreset.contains("256") ? "256" : "224"}px input',
                      Icons.crop_free,
                    ),
                    _buildDetailChip(
                      theme,
                      '${_getEmbeddingDim(capabilities.recommendedModelPreset)}D embedding',
                      Icons.table_chart,
                    ),
                    _buildDetailChip(
                      theme,
                      '~${capabilities.performanceMultiplier.toStringAsFixed(1)}x speed',
                      Icons.speed,
                    ),
                    _buildDetailChip(
                      theme,
                      capabilities.useGpuDelegate ? 'GPU/NPU accelerated' : 'CPU only',
                      capabilities.useGpuDelegate ? Icons.memory : Icons.memory_outlined,
                    ),
                    _buildDetailChip(
                      theme,
                      '${capabilities.maxBatchSize} batch',
                      Icons.layers,
                    ),
                  ],
                ),
                if (recommendedPreset != null) ...[
                  const SizedBox(height: 12),
                  _buildModelDetails(theme, recommendedPreset),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _getModelDisplayName(String preset) {
    return switch (preset) {
      'mobileclip-s1' => 'MobileCLIP-S1 (Fastest, 512-dim)',
      'mobileclip-s2' => 'MobileCLIP-S2 (Balanced, 512-dim)',
      'siglip-base-patch16-224' => 'SigLIP-B/16-224 (Best Quality, 768-dim)',
      'siglip-base-patch16-256' => 'SigLIP-B/16-256 (Highest Quality, 768-dim)',
      'clip-vit-base-patch32' => 'CLIP-ViT-B/32 (512-dim)',
      _ => preset,
    };
  }

  int _getEmbeddingDim(String preset) {
    return switch (preset) {
      'mobileclip-s1' => 512,
      'mobileclip-s2' => 512,
      'siglip-base-patch16-224' => 768,
      'siglip-base-patch16-256' => 768,
      'clip-vit-base-patch32' => 512,
      _ => 768,
    };
  }

  Widget _buildStatChip(ThemeData theme, String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyInstalled(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.model_training_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No models installed',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Download a model below to enable semantic search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledModelTile(
    ThemeData theme,
    DownloadedModel model,
    ModelManager modelManager,
    AppLogger logger,
  ) {
    final preset = ModelPresets.presets.entries
        .where((e) => e.value.resolvedLocalName == model.name)
        .map((e) => e.value)
        .firstOrNull;

    // Get state icon and color
    final (stateIcon, stateColor, stateText) = _getStateDisplay(model.state, model.errorMessage);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  stateIcon,
                  color: stateColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset?.description ?? model.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        model.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (model.state != ModelState.installed && model.state != ModelState.ready)
                        Text(
                          stateText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: stateColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (model.state == ModelState.failed)
                  OutlinedButton.icon(
                    onPressed: () => _deleteModel(model, modelManager, logger),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.data_usage_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  model.sizeFormatted,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Updated ${_formatDate(model.modifiedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (model.state == ModelState.installed || model.state == ModelState.ready)
                  OutlinedButton.icon(
                    onPressed: () => _deleteModel(model, modelManager, logger),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
            if (preset != null) ...[
              const SizedBox(height: 8),
              _buildModelDetails(theme, preset),
            ],
            if (model.errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Get display info for a model state.
  (IconData, Color, String) _getStateDisplay(ModelState state, String? errorMessage) {
    return switch (state) {
      ModelState.installed => (Icons.check_circle, Colors.green, 'Installed'),
      ModelState.ready => (Icons.check_circle, Colors.green, 'Ready'),
      ModelState.loading => (Icons.hourglass_top, Colors.orange, 'Loading...'),
      ModelState.downloading => (Icons.cloud_download, Colors.blue, 'Downloading...'),
      ModelState.verifying => (Icons.verified, Colors.blue, 'Verifying...'),
      ModelState.failed => (Icons.error, Colors.red, 'Failed: ${errorMessage ?? "Unknown error"}'),
      ModelState.notInstalled => (Icons.cloud_off, Colors.grey, 'Not installed'),
    };
  }

  Widget _buildAvailableModelTile(
    ThemeData theme,
    ModelConfig preset,
    List<DownloadedModel> downloadedModels,
    ModelManager modelManager,
    AppLogger logger,
  ) {
    final isInstalled = downloadedModels.any((m) => m.name == preset.resolvedLocalName);
    final existingModel = downloadedModels.where((m) => m.name == preset.resolvedLocalName).firstOrNull;

    // Check if this model is currently being downloaded
    final isDownloading = modelManager.selectedModel == preset.resolvedLocalName &&
        (modelManager.getDownloadState() == ModelState.downloading ||
         modelManager.getDownloadState() == ModelState.verifying);

    // Get state for display
    ModelState displayState = ModelState.notInstalled;
    if (isInstalled) {
      displayState = existingModel?.state ?? ModelState.installed;
    } else if (isDownloading) {
      displayState = modelManager.getDownloadState();
    }

    final (stateIcon, stateColor, stateText) = _getStateDisplay(displayState, existingModel?.errorMessage);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  stateIcon,
                  color: stateColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.description,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Model ID: ${preset.modelId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isDownloading || (displayState != ModelState.installed && displayState != ModelState.ready && displayState != ModelState.notInstalled))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            stateText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: stateColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isInstalled && !isDownloading)
                  FilledButton.icon(
                    onPressed: () => _downloadModel(preset, modelManager, logger),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  )
                else if (isDownloading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isInstalled)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Installed'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildDetailChip(theme, '${preset.inputSize}px', Icons.crop_free),
                const SizedBox(width: 8),
                _buildDetailChip(theme, '${preset.embeddingDim}D', Icons.table_chart),
                const SizedBox(width: 8),
                _buildDetailChip(theme, _estimateModelSize(preset), Icons.data_usage),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(ThemeData theme, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelDetails(ThemeData theme, ModelConfig preset) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(theme, 'Input Size', '${preset.inputSize} × ${preset.inputSize}'),
          _buildDetailRow(theme, 'Embedding Dimension', '${preset.embeddingDim}'),
          _buildDetailRow(theme, 'Model ID', preset.modelId),
          _buildDetailRow(theme, 'Filename', preset.filename),
        ],
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _estimateModelSize(ModelConfig preset) {
    // Rough estimates based on model type
    if (preset.modelId.contains('mobileclip-s1')) return '~60 MB';
    if (preset.modelId.contains('mobileclip-s2')) return '~120 MB';
    if (preset.modelId.contains('siglip-base-patch16-224')) return '~350 MB';
    if (preset.modelId.contains('siglip-base-patch16-256')) return '~400 MB';
    if (preset.modelId.contains('clip-vit-base-patch32')) return '~300 MB';
    return 'Unknown';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Future<void> _downloadModel(ModelConfig preset, ModelManager modelManager, AppLogger logger) async {
    // Show progress dialog
    if (!context.mounted) return;

    modelManager.selectModel(preset.resolvedLocalName);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(
        modelManager: modelManager,
        preset: preset,
      ),
    ).then((_) {
      // Refresh the stream after dialog closes
      _downloadedModelsStream = _watchDownloadedModels();
      if (mounted) setState(() {});
    });
  }

  Future<void> _deleteModel(DownloadedModel model, ModelManager modelManager, AppLogger logger) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model?'),
        content: Text('Remove "${model.name}" (${model.sizeFormatted})? Semantic search will not work until you download a model.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await modelManager.deleteModel(model.name);
        logger.info('Deleted model: ${model.name}');
      } catch (e, st) {
        logger.error('Failed to delete model', error: e, stackTrace: st);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }
}

class _DownloadProgressDialog extends ConsumerStatefulWidget {
  const _DownloadProgressDialog({
    required this.modelManager,
    required this.preset,
  });

  final ModelManager modelManager;
  final ModelConfig preset;

  @override
  ConsumerState<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends ConsumerState<_DownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Preparing...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    final logger = ref.read(di_providers.appLoggerProvider);

    try {
      setState(() {
        _status = 'Downloading...';
        _progress = 0.0;
      });

      final result = await widget.modelManager.getSelectedModelPath(
        progressCallback: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status = 'Downloading... ${(p * 100).toInt()}%';
            });
          }
        },
        stateCallback: (state) {
          if (mounted) {
            setState(() {
              switch (state) {
                case ModelState.downloading:
                  _status = 'Downloading... ${(_progress * 100).toInt()}%';
                  break;
                case ModelState.verifying:
                  _status = 'Verifying model...';
                  break;
                case ModelState.installed:
                  _status = 'Download complete!';
                  _progress = 1.0;
                  break;
                case ModelState.failed:
                  _status = 'Failed';
                  break;
                default:
                  break;
              }
            });
          }
        },
      );

      if (mounted) {
        if (result.isSuccess) {
          setState(() {
            _progress = 1.0;
            _status = 'Download complete!';
          });
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) Navigator.pop(context);
        } else {
          setState(() {
            _error = 'Download failed: ${result.errorMessage ?? 'Unknown error'}';
            _status = 'Failed';
          });
        }
      }
    } catch (e, st) {
      logger.error('Model download failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = 'Download failed: $e';
          _status = 'Failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('Downloading ${widget.preset.description}'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            Text(_status),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        if (_progress > 0 && _progress < 1.0 && _error == null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}