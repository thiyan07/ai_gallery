import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../domain/models/index_status.dart';

class IndexingScreen extends ConsumerWidget {
  const IndexingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final indexingEngineAsync = ref.watch(indexingEngineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Index Photos'),
      ),
      body: indexingEngineAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Failed to initialize indexing engine: $error'),
        ),
        data: (indexingEngine) {
          return StreamBuilder<IndexStatus>(
            stream: indexingEngine.statusStream,
            initialData: indexingEngine.currentStatus,
            builder: (context, snapshot) {
              final status = snapshot.data ?? IndexStatus.initial;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Overview
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  status.isRunning
                                      ? Icons.play_arrow
                                      : status.isPaused
                                          ? Icons.pause
                                          : Icons.stop,
                                  color: status.isRunning
                                      ? Colors.green
                                      : status.isPaused
                                          ? Colors.orange
                                          : Colors.grey,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  status.isRunning
                                      ? (status.isPaused ? 'Paused' : 'Indexing')
                                      : 'Not running',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Progress Bar
                            if (status.totalPhotos > 0) ...[
                              LinearProgressIndicator(
                                value: status.progress,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${status.processedPhotos} / ${status.totalPhotos} photos (${status.failedPhotos} failed)',
                              ),
                              if (status.etaSeconds != null)
                                Text(
                                  'ETA: ${(status.etaSeconds! / 60).toStringAsFixed(1)} minutes',
                                ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              'Current phase: ${_getPhaseName(status.currentPhase)}',
                            ),
                            if (status.currentPhotoId != null)
                              Text(
                                'Processing photo: ${status.currentPhotoId}',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!status.isRunning)
                          FilledButton.icon(
                            onPressed: () => indexingEngine.start(),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Indexing'),
                          ),
                        if (status.isRunning && !status.isPaused) ...[
                          FilledButton.icon(
                            onPressed: () => indexingEngine.pause(),
                            icon: const Icon(Icons.pause),
                            label: const Text('Pause'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => indexingEngine.cancel(),
                            icon: const Icon(Icons.stop),
                            label: const Text('Cancel'),
                          ),
                        ],
                        if (status.isRunning && status.isPaused) ...[
                          FilledButton.icon(
                            onPressed: () => indexingEngine.resume(),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Resume'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => indexingEngine.cancel(),
                            icon: const Icon(Icons.stop),
                            label: const Text('Cancel'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _getPhaseName(IndexingPhase phase) {
    switch (phase) {
      case IndexingPhase.scanning:
        return 'Scanning gallery';
      case IndexingPhase.extractingMetadata:
        return 'Extracting metadata';
      case IndexingPhase.generatingThumbnails:
        return 'Generating thumbnails';
      case IndexingPhase.analyzingColors:
        return 'Analyzing colors';
      case IndexingPhase.detectingBlur:
        return 'Detecting blur';
      case IndexingPhase.calculatingQuality:
        return 'Calculating quality score';
      case IndexingPhase.generatingEmbeddings:
        return 'Generating embeddings';
      case IndexingPhase.ocr:
        return 'Running OCR';
      case IndexingPhase.detectingObjects:
        return 'Detecting objects';
      case IndexingPhase.detectingFaces:
        return 'Detecting faces';
      case IndexingPhase.complete:
        return 'Complete';
    }
  }
}
