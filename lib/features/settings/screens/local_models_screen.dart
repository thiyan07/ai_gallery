import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/core/di/providers.dart' as di_providers;
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';

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
                  Icons.check_circle,
                  color: Colors.green,
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
                    ],
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
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableModelTile(
    ThemeData theme,
    ModelConfig preset,
    List<DownloadedModel> downloadedModels,
    ModelManager modelManager,
    AppLogger logger,
  ) {
    final isInstalled = downloadedModels.any((m) => m.name == preset.resolvedLocalName);
    final isDownloading = modelManager.selectedModel == preset.resolvedLocalName;

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
                  isInstalled ? Icons.check_circle : Icons.cloud_download,
                  color: isInstalled ? Colors.green : theme.colorScheme.primary,
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
                    ],
                  ),
                ),
                if (!isInstalled)
                  isDownloading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: () => _downloadModel(preset, modelManager, logger),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        )
                else
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
    );
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

      final path = await widget.modelManager.getSelectedModelPath(
        progressCallback: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status = 'Downloading... ${(p * 100).toInt()}%';
            });
          }
        },
      );

      if (mounted) {
        if (path != null) {
          setState(() {
            _progress = 1.0;
            _status = 'Download complete!';
          });
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) Navigator.pop(context);
        } else {
          setState(() {
            _error = 'Download failed: Unknown error';
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