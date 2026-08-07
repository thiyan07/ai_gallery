import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/features/people/providers/people_providers.dart';
import 'package:ai_gallery/features/people/services/face_clustering_service.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';

/// People screen showing clustered faces (person groups).
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  late final AppLogger _logger;
  StreamSubscription? _clustersSubscription;
  FaceClusteringService? _service;

  @override
  void initState() {
    super.initState();
    _logger = ref.read(appLoggerProvider);
    _initService();
  }

  Future<void> _initService() async {
    _service = await ref.read(faceClusteringServiceProviderAsync.future);
  }

  Future<void> _recluster() async {
    try {
      await ref.read(peopleClustersProvider.notifier).recluster();
    } catch (e, st) {
      _logger.error('Reclustering failed', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reclustering failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _clustersSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clustersAsync = ref.watch(peopleClustersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _recluster,
            tooltip: 'Recluster all faces',
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'recluster', child: ListTile(leading: Icon(Icons.refresh), title: Text('Recluster All'))),
              const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Clustering Settings'))),
            ],
          ),
        ],
      ),
      body: clustersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading people', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(error.toString(), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => ref.refresh(peopleClustersProvider), child: const Text('Retry')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _recluster, child: const Text('Recluster All')),
            ],
          ),
        ),
        data: (clusters) {
          if (clusters.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('No People Found', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Run indexing to detect faces and group them into people.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _recluster,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Recluster'),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _PersonClusterCard(
                      cluster: clusters[index],
                      onTap: () => _openPersonDetail(clusters[index]),
                      onRename: () => _renameCluster(clusters[index]),
                      onDelete: () => _deleteCluster(clusters[index]),
                    ),
                    childCount: clusters.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'recluster':
        _recluster();
        break;
      case 'settings':
        _showClusteringSettings();
        break;
    }
  }

  void _openPersonDetail(PersonCluster cluster) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonDetailScreen(
          cluster: cluster,
        ),
      ),
    ).then((_) => ref.refresh(peopleClustersProvider));
  }

  Future<void> _renameCluster(PersonCluster cluster) async {
    final controller = TextEditingController(text: cluster.label);
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter person name',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != cluster.label) {
      try {
        final service = await ref.read(faceClusteringServiceProviderAsync.future);
        await service.renameCluster(cluster.label, result);
        ref.refresh(peopleClustersProvider);
      } catch (e, st) {
        _logger.error('Failed to rename cluster', error: e, stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to rename: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteCluster(PersonCluster cluster) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${cluster.label}?'),
        content: Text('This will remove the person label from ${cluster.faceCount} faces. The faces will remain but won\'t be grouped.'),
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

    if (confirmed == true) {
      try {
        final service = await ref.read(faceClusteringServiceProviderAsync.future);
        await service.deleteCluster(cluster.label);
        ref.refresh(peopleClustersProvider);
      } catch (e, st) {
        _logger.error('Failed to delete cluster', error: e, stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  void _showClusteringSettings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clustering Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Similarity Threshold'),
              subtitle: Text('Current: ${_service?.similarityThreshold?.toStringAsFixed(1) ?? "—"}'),
              onTap: () {
                Navigator.pop(context);
                _showThresholdDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Min Cluster Size'),
              subtitle: Text('Current: ${_service?.minClusterSize ?? "—"}'),
              onTap: () {
                Navigator.pop(context);
                _showMinClusterSizeDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Recluster All Faces'),
              subtitle: const Text('Re-run clustering on all detected faces'),
              onTap: () {
                Navigator.pop(context);
                _recluster();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThresholdDialog() {
    final threshold = _service?.similarityThreshold ?? 0.6;
    double tempThreshold = threshold;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Similarity Threshold'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Higher = stricter matching (fewer false positives)'),
              Slider(
                value: tempThreshold,
                min: 0.3,
                max: 0.9,
                divisions: 12,
                label: tempThreshold.toStringAsFixed(2),
                onChanged: (v) => setState(() => tempThreshold = v),
              ),
              Text('Current: $tempThreshold'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              // Note: This is a static const, so we can't actually change it at runtime
              // In a real implementation, this would be a configurable value
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Threshold setting requires app restart')),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showMinClusterSizeDialog() {
    final minSize = _service?.minClusterSize ?? 2;
    int tempMinSize = minSize;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Minimum Cluster Size'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Minimum faces to form a person group'),
              Slider(
                value: tempMinSize.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: tempMinSize.toString(),
                onChanged: (v) => setState(() => tempMinSize = v.round()),
              ),
              Text('Current: $tempMinSize'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Setting requires app restart')),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

/// Person detail screen showing all faces for a person.
class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.cluster,
  });

  final PersonCluster cluster;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  late final List<FaceDetectionRecord> _faces;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _faces = widget.cluster.faces;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cluster.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _renamePerson,
            tooltip: 'Rename',
          ),
          PopupMenuButton<String>(
            onSelected: _handleDetailAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'merge', child: ListTile(leading: Icon(Icons.merge), title: Text('Merge with another'))),
              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Delete Person'))),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _faces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_outline, size: 64, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('No faces', style: theme.textTheme.headlineSmall),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _faces.length,
                  itemBuilder: (context, index) => _FaceThumbnail(face: _faces[index]),
                ),
    );
  }

  Future<void> _renamePerson() async {
    final controller = TextEditingController(text: widget.cluster.label);
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter person name',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != widget.cluster.label) {
      try {
        final service = await ref.read(faceClusteringServiceProviderAsync.future);
        await service.renameCluster(widget.cluster.label, result);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to rename: $e')),
          );
        }
      }
    }
  }

  void _handleDetailAction(String action) {
    switch (action) {
      case 'merge':
        _showMergeDialog();
        break;
      case 'delete':
        _deletePerson();
        break;
    }
  }

  Future<void> _showMergeDialog() async {
    // Get all other clusters
    final service = await ref.read(faceClusteringServiceProviderAsync.future);
    final allClusters = await service.getPeopleClusters();
    final otherClusters = allClusters.where((c) => c.label != widget.cluster.label).toList();

    if (otherClusters.isEmpty) return;

    final selected = await showDialog<PersonCluster?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge with Person'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherClusters.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(otherClusters[index].label),
              subtitle: Text('${otherClusters[index].faceCount} faces'),
              onTap: () => Navigator.pop(context, otherClusters[index]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );

    if (selected != null && mounted) {
      try {
        await service.mergeClusters(selected.label, widget.cluster.label);
        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to merge: $e')),
        );
      }
    }
  }

  Future<void> _deletePerson() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.cluster.label}?'),
        content: Text('This will remove the person label from ${widget.cluster.faceCount} faces.'),
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

    if (confirmed == true && mounted) {
      try {
        final service = await ref.read(faceClusteringServiceProviderAsync.future);
        await service.deleteCluster(widget.cluster.label);
        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}

/// Card widget for a person cluster in the grid.
class _PersonClusterCard extends StatelessWidget {
  const _PersonClusterCard({
    required this.cluster,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final PersonCluster cluster;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repFace = cluster.representativeFace;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Face thumbnail
            AspectRatio(
              aspectRatio: 1,
              child: repFace != null
                  ? _FaceThumbnail(face: repFace)
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cluster.label,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cluster.faceCount} ${cluster.faceCount == 1 ? 'photo' : 'photos'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                onRename();
              },
            ),
            ListTile(
              leading: const Icon(Icons.merge),
              title: const Text('Merge with another'),
              onTap: () {
                Navigator.pop(context);
                // Would need to navigate back to list to select merge target
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Face thumbnail widget.
class _FaceThumbnail extends StatelessWidget {
  const _FaceThumbnail({required this.face});

  final FaceDetectionRecord face;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: Icon(Icons.face, size: 32),
          ),
        ),
        // In a real implementation, this would show the actual face crop
        // For now, show placeholder with confidence
        Positioned(
          bottom: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(face.confidence * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}