import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/providers.dart';
import '../../../../domain/models/index_status.dart';
import '../../../../domain/models/ai_job.dart';

class IndexingScreen extends ConsumerWidget {
  const IndexingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final indexingEngineAsync = ref.watch(indexingEngineProvider);
    final pendingJobsAsync = ref.watch(pendingJobsProvider);
    final failedJobsAsync = ref.watch(failedJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Index Photos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(pendingJobsProvider);
              ref.invalidate(failedJobsProvider);
            },
            tooltip: 'Refresh job status',
          ),
        ],
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
              return ListView(
                padding: const EdgeInsets.all(16.0),
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
                  // Embedding Job Status
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Job Progress',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          _JobStatusSection(
                            title: 'Pending Jobs',
                            jobsAsync: pendingJobsAsync,
                            icon: Icons.schedule,
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 8),
                          _JobStatusSection(
                            title: 'Failed Jobs',
                            jobsAsync: failedJobsAsync,
                            icon: Icons.error,
                            color: Colors.red,
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
                  const SizedBox(height: 24),
                  // Statistics
                  _StatisticsSection(database: ref.watch(appDatabaseProvider).requireValue),
                ],
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

class _JobStatusSection extends ConsumerWidget {
  const _JobStatusSection({
    required this.title,
    required this.jobsAsync,
    required this.icon,
    required this.color,
  });

  final String title;
  final AsyncValue<List<AIJob>> jobsAsync;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return jobsAsync.when(
      loading: () => const SizedBox(
        height: 50,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Text('Error loading jobs: $e'),
      data: (jobs) {
        if (jobs.isEmpty) {
          return Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text('$title: None', style: Theme.of(context).textTheme.bodyMedium),
            ],
          );
        }

        // Group by status
        final grouped = <AIJobStatus, List<AIJob>>{};
        for (final job in jobs) {
          grouped.putIfAbsent(job.status, () => []).add(job);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  '$title (${jobs.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...grouped.entries.map((entry) {
              final status = entry.key;
              final statusJobs = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 28),
                    _StatusBadge(status: status, count: statusJobs.length),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_formatJobType(statusJobs.first.type)} × ${statusJobs.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (status == AIJobStatus.failed && statusJobs.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          // Retry all failed jobs of this type
                          final jobQueue = await ref.read(backgroundJobQueueProvider.future);
                          for (final job in statusJobs) {
                            jobQueue.enqueue(job.copyWith(
                              status: AIJobStatus.pending,
                              errorMessage: null,
                              progress: 0.0,
                            ));
                          }
                        },
                        child: const Text('Retry All'),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  String _formatJobType(AIJobType type) {
    switch (type) {
      case AIJobType.embedding:
        return 'Embeddings';
      case AIJobType.faceDetection:
        return 'Face Detection';
      case AIJobType.objectTagging:
        return 'Object Detection';
      case AIJobType.ocr:
        return 'OCR';
      case AIJobType.caption:
        return 'Captions';
      case AIJobType.faceEmbedding:
        return 'Face Embeddings';
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.count});

  final AIJobStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case AIJobStatus.pending:
        color = Colors.grey;
        label = 'Pending';
        break;
      case AIJobStatus.running:
        color = Colors.blue;
        label = 'Running';
        break;
      case AIJobStatus.completed:
        color = Colors.green;
        label = 'Done';
        break;
      case AIJobStatus.failed:
        color = Colors.red;
        label = 'Failed';
        break;
      case AIJobStatus.cancelled:
        color = Colors.orange;
        label = 'Cancelled';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        '$label ($count)',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatisticsSection extends ConsumerWidget {
  const _StatisticsSection({required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return FutureBuilder<Map<String, int>>(
      future: _fetchStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final stats = snapshot.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Index Statistics',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _StatChip(label: 'Embeddings', value: stats['embeddings']?.toString() ?? '0', icon: Icons.psychology),
                    _StatChip(label: 'Faces', value: stats['faces']?.toString() ?? '0', icon: Icons.face),
                    _StatChip(label: 'Objects', value: stats['objects']?.toString() ?? '0', icon: Icons.label),
                    _StatChip(label: 'OCR Text', value: stats['ocr']?.toString() ?? '0', icon: Icons.text_fields),
                    _StatChip(label: 'Favorites', value: stats['favorites']?.toString() ?? '0', icon: Icons.star),
                    _StatChip(label: 'Indexed Photos', value: stats['photos']?.toString() ?? '0', icon: Icons.photo_library),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _fetchStats() async {
    final results = <String, int>{};

    try {
      results['embeddings'] = Sqflite.firstIntValue(
        await database.database.rawQuery('SELECT COUNT(*) FROM embeddings'),
      ) ?? 0;
    } catch (_) {}

    try {
      results['faces'] = Sqflite.firstIntValue(
        await database.database.rawQuery('SELECT COUNT(*) FROM faces'),
      ) ?? 0;
    } catch (_) {}

    try {
      results['objects'] = Sqflite.firstIntValue(
        await database.database.rawQuery('SELECT COUNT(*) FROM object_tags'),
      ) ?? 0;
    } catch (_) {}

    try {
      results['ocr'] = Sqflite.firstIntValue(
        await database.database.rawQuery('SELECT COUNT(*) FROM ocr_text'),
      ) ?? 0;
    } catch (_) {}

    try {
      results['favorites'] = Sqflite.firstIntValue(
        await database.database.rawQuery('SELECT COUNT(*) FROM favorites'),
      ) ?? 0;
    } catch (_) {}

    try {
      results['photos'] = Sqflite.firstIntValue(
        await database.database.rawQuery('SELECT COUNT(*) FROM photo_metadata'),
      ) ?? 0;
    } catch (_) {}

    return results;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
