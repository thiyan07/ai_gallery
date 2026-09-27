import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'dart:async';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/features/people/providers/people_providers.dart';
import 'package:ai_gallery/features/people/services/face_clustering_service.dart';
import 'package:ai_gallery/features/people/services/people_service.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/person_cluster.dart';

const _maxNameLength = 50;

/// People screen showing clustered faces with Named/Unknown tabs.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen>
    with SingleTickerProviderStateMixin {
  late final AppLogger _logger;
  late final TabController _tabController;
  FaceClusteringService? _service;

  @override
  void initState() {
    super.initState();
    _logger = ref.read(appLoggerProvider);
    _tabController = TabController(length: 2, vsync: this);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reclustering failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clustersAsync = ref.watch(peopleClustersProvider);
    final isLoading = clustersAsync.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48 + 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Named'),
                  Tab(text: 'Unknown'),
                ],
              ),
              if (isLoading)
                const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : _recluster,
            tooltip: 'Recluster all faces',
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'recluster',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Recluster All'),
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Clustering Settings'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: clustersAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Processing faces…'),
            ],
          ),
        ),
        error: (error, stack) => _buildErrorState(theme, error),
        data: (clusters) {
          if (clusters.isEmpty) return _buildEmptyState(theme);
          return _buildClusteredView(clusters);
        },
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text('Error loading people', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.refresh(peopleClustersProvider),
            child: const Text('Retry'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _recluster,
            child: const Text('Recluster All'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('No People Found', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Run indexing to detect faces and group them into people.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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

  Widget _buildClusteredView(List<PersonCluster> clusters) {
    final namedClusters = clusters.where((c) => !c.isUnknown).toList();
    final unknownClusters = clusters.where((c) => c.isUnknown).toList();

    return TabBarView(
      controller: _tabController,
      children: [
        _buildClusterGrid(namedClusters, emptyMessage: 'No named people yet'),
        _buildClusterGrid(unknownClusters, emptyMessage: 'No unknown groups'),
      ],
    );
  }

  Widget _buildClusterGrid(List<PersonCluster> clusters, {required String emptyMessage}) {
    if (clusters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 360 ? 2 : width < 600 ? 3 : 4;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemCount: clusters.length,
          itemBuilder: (context, index) => _PersonClusterCard(
            cluster: clusters[index],
            onTap: () => _openPersonDetail(clusters[index]),
            onRename: () => _renameCluster(clusters[index]),
            onDelete: () => _deleteCluster(clusters[index]),
            onMerge: () => _openPersonDetail(clusters[index]),
          ),
        );
      },
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
      MaterialPageRoute(builder: (_) => PersonDetailScreen(cluster: cluster)),
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
          maxLength: _maxNameLength,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter person name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != cluster.label) {
      if (result.length > _maxNameLength) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Name too long (max $_maxNameLength characters)')),
          );
        }
        return;
      }
      try {
        final service = await ref.read(
          faceClusteringServiceProviderAsync.future,
        );
        await service.renameCluster(cluster.label, result);
        // ignore: unused_result
        ref.refresh(peopleClustersProvider);
      } catch (e, st) {
        _logger.error('Failed to rename cluster', error: e, stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
        }
      }
    }
  }

  Future<void> _deleteCluster(PersonCluster cluster) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${cluster.label}?'),
        content: Text(
          'This will remove the person label from ${cluster.faceCount} '
          '${cluster.faceCount == 1 ? 'face' : 'faces'}. '
          'The faces will remain but won\'t be grouped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = await ref.read(
          faceClusteringServiceProviderAsync.future,
        );
        await service.deleteCluster(cluster.label);
        // ignore: unused_result
        ref.refresh(peopleClustersProvider);
      } catch (e, st) {
        _logger.error('Failed to delete cluster', error: e, stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
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
            Text(
              'Clustering Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Similarity Threshold'),
              subtitle: Text(
                'Current: ${_service?.similarityThreshold.toStringAsFixed(1) ?? "—"}',
              ),
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
              const Text('Higher = stricter matching (fewer false positives)'),
              Slider(
                value: tempThreshold,
                min: 0.3,
                max: 0.9,
                divisions: 12,
                label: tempThreshold.toStringAsFixed(2),
                onChanged: (v) => setState(() => tempThreshold = v),
              ),
              Text('Current: ${tempThreshold.toStringAsFixed(2)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Threshold setting requires app restart'),
                ),
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
              const Text('Minimum faces to form a person group'),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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

/// Person detail screen showing all faces and face operations.
class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({super.key, required this.cluster});

  final PersonCluster cluster;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  late List<FaceDetectionRecord> _faces;
  late final AppLogger _logger;
  late final AppDatabase _database;
  bool _isLoading = false;
  bool _isSplitMode = false;
  final Set<String> _selectedFaceIds = {};

  @override
  void initState() {
    super.initState();
    _logger = ref.read(appLoggerProvider);
    _database = ref.read(appDatabaseProvider).requireValue;
    _faces = widget.cluster.faces;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoCount = _faces.map((f) => f.photoId).toSet().length;

    return Scaffold(
      appBar: AppBar(
        title: _isSplitMode
            ? Text('${_selectedFaceIds.length} selected')
            : Text(widget.cluster.label),
        leading: _isSplitMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSplitMode,
              )
            : null,
        actions: _isSplitMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select all',
                  onPressed: () => setState(() {
                    _selectedFaceIds.addAll(_faces.map((f) => f.id));
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'Move selected',
                  onPressed: _selectedFaceIds.isEmpty ? null : _showMoveSelectedDialog,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _renamePerson,
                  tooltip: 'Rename',
                ),
                PopupMenuButton<String>(
                  onSelected: _handleDetailAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'merge',
                      child: ListTile(
                        leading: Icon(Icons.merge),
                        title: Text('Merge with another'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'split',
                      child: ListTile(
                        leading: Icon(Icons.content_cut),
                        title: Text('Split (move faces)'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'set_cover',
                      child: ListTile(
                        leading: Icon(Icons.photo_library),
                        title: Text('Set cover photo'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete),
                        title: Text('Delete Person'),
                      ),
                    ),
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
                      Icon(
                        Icons.person_outline,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text('No faces', style: theme.textTheme.headlineSmall),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Face/photo count header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.face,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_faces.length} ${_faces.length == 1 ? 'face' : 'faces'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Face grid
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: _faces.length,
                        itemBuilder: (context, index) {
                          final face = _faces[index];
                          if (_isSplitMode) {
                            return _FaceThumbnail(
                              face: face,
                              isSelected: _selectedFaceIds.contains(face.id),
                              onTap: () => _toggleFaceSelection(face.id),
                            );
                          }
                          return _FaceThumbnail(
                            face: face,
                            onTap: () => _showFaceActions(face),
                            onLongPress: () => _enterSplitModeWith(face.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  void _handleDetailAction(String action) {
    switch (action) {
      case 'merge':
        _showMergeDialog();
        break;
      case 'split':
        _enterSplitMode();
        break;
      case 'set_cover':
        _showSetCoverDialog();
        break;
      case 'delete':
        _deletePerson();
        break;
    }
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
          maxLength: _maxNameLength,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter person name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != widget.cluster.label) {
      if (result.length > _maxNameLength) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Name too long (max $_maxNameLength characters)')),
          );
        }
        return;
      }
      try {
        final service = await ref.read(
          faceClusteringServiceProviderAsync.future,
        );
        await service.renameCluster(widget.cluster.label, result);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
        }
      }
    }
  }

  // ─────────────────────────────────────────────
  // Face Actions
  // ─────────────────────────────────────────────

  void _showFaceActions(FaceDetectionRecord face) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('View Photo'),
              onTap: () {
                Navigator.pop(context);
                _viewPhoto(face);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Move to Another Person'),
              onTap: () {
                Navigator.pop(context);
                _showMoveFaceDialog(face);
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Mark as Unknown'),
              onTap: () {
                Navigator.pop(context);
                _markAsUnknown(face);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
              title: const Text('Remove from Person', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _removeFaceFromPerson(face);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewPhoto(FaceDetectionRecord face) async {
    final asset = await AssetEntity.fromId(face.photoId);
    if (!mounted || asset == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('Photo with ${widget.cluster.label}'),
          ),
          body: Center(
            child: AssetEntityImage(
              asset,
              isOriginal: true,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMoveFaceDialog(FaceDetectionRecord face) async {
    try {
      final service = await ref.read(
        faceClusteringServiceProviderAsync.future,
      );
      if (!mounted) return;
      final allClusters = await service.getPeopleClusters();
      if (!mounted) return;

      final otherClusters = allClusters
          .where((c) => c.label != widget.cluster.label)
          .toList();

      if (otherClusters.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No other people to move to')),
          );
        }
        return;
      }

      final selected = await showDialog<PersonCluster?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Move Face To'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: otherClusters.length,
              itemBuilder: (context, index) => ListTile(
                leading: const Icon(Icons.person),
                title: Text(otherClusters[index].label),
                subtitle: Text('${otherClusters[index].faceCount} faces'),
                onTap: () => Navigator.pop(context, otherClusters[index]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selected != null && mounted) {
        final peopleService = PeopleService(
          logger: _logger,
          database: _database,
        );
        await peopleService.moveFace(face.id, selected.label);
        if (!mounted) return;
        setState(() {
          _faces = _faces.where((f) => f.id != face.id).toList();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Face moved to ${selected.label}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to move face: $e')));
      }
    }
  }

  Future<void> _markAsUnknown(FaceDetectionRecord face) async {
    try {
      final peopleService = PeopleService(
        logger: _logger,
        database: _database,
      );
      await peopleService.removeFaceFromPerson(face.id);
      if (!mounted) return;
      setState(() {
        _faces = _faces.where((f) => f.id != face.id).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Face marked as unknown')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _removeFaceFromPerson(FaceDetectionRecord face) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Face?'),
        content: const Text(
          'This face will be removed from this person. It won\'t be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final peopleService = PeopleService(
          logger: _logger,
          database: _database,
        );
        await peopleService.removeFaceFromPerson(face.id);
        if (!mounted) return;
        setState(() {
          _faces = _faces.where((f) => f.id != face.id).toList();
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to remove face: $e')));
        }
      }
    }
  }

  // ─────────────────────────────────────────────
  // Split Mode
  // ─────────────────────────────────────────────

  void _enterSplitMode() {
    setState(() {
      _isSplitMode = true;
      _selectedFaceIds.clear();
    });
  }

  void _enterSplitModeWith(String faceId) {
    setState(() {
      _isSplitMode = true;
      _selectedFaceIds.clear();
      _selectedFaceIds.add(faceId);
    });
  }

  void _exitSplitMode() {
    setState(() {
      _isSplitMode = false;
      _selectedFaceIds.clear();
    });
  }

  void _toggleFaceSelection(String faceId) {
    setState(() {
      if (_selectedFaceIds.contains(faceId)) {
        _selectedFaceIds.remove(faceId);
      } else {
        _selectedFaceIds.add(faceId);
      }
    });
  }

  Future<void> _showMoveSelectedDialog() async {
    try {
      final service = await ref.read(
        faceClusteringServiceProviderAsync.future,
      );
      if (!mounted) return;
      final allClusters = await service.getPeopleClusters();
      if (!mounted) return;

      final otherClusters = allClusters
          .where((c) => c.label != widget.cluster.label)
          .toList();

      final destinations = <String, String?>{
        for (final c in otherClusters) c.label: c.label,
      };
      destinations['Unknown'] = null;

      final selected = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Move ${_selectedFaceIds.length} faces to'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final label = destinations.keys.elementAt(index);
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(label),
                  onTap: () => Navigator.pop(context, label),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selected != null && mounted) {
        final peopleService = PeopleService(
          logger: _logger,
          database: _database,
        );
        final destinationLabel = destinations[selected];
        final faceIds = _selectedFaceIds.toList();

        for (final faceId in faceIds) {
          if (!mounted) return;
          if (destinationLabel != null) {
            await peopleService.moveFace(faceId, destinationLabel);
          } else {
            await peopleService.removeFaceFromPerson(faceId);
          }
        }

        if (!mounted) return;
        setState(() {
          _faces = _faces.where((f) => !_selectedFaceIds.contains(f.id)).toList();
          _isSplitMode = false;
          _selectedFaceIds.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Moved ${faceIds.length} faces to $selected')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to move faces: $e')));
      }
    }
  }

  // ─────────────────────────────────────────────
  // Merge
  // ─────────────────────────────────────────────

  Future<void> _showMergeDialog() async {
    final service = await ref.read(faceClusteringServiceProviderAsync.future);
    if (!mounted) return;
    final allClusters = await service.getPeopleClusters();
    if (!mounted) return;
    final otherClusters = allClusters
        .where((c) => c.label != widget.cluster.label)
        .toList();

    if (otherClusters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other people to merge with')),
        );
      }
      return;
    }

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
              leading: const Icon(Icons.person),
              title: Text(otherClusters[index].label),
              subtitle: Text('${otherClusters[index].faceCount} faces'),
              onTap: () => Navigator.pop(context, otherClusters[index]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Merge'),
          content: Text(
            'Merge "${widget.cluster.label}" into "${selected.label}"? '
            '${_faces.length} faces will be moved to "${selected.label}". '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Merge'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        try {
          await service.mergeClusters(selected.label, widget.cluster.label);
          if (mounted) Navigator.pop(context, true);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to merge: $e')),
            );
          }
        }
      }
    }
  }

  // ─────────────────────────────────────────────
  // Set Cover Photo
  // ─────────────────────────────────────────────

  Future<void> _showSetCoverDialog() async {
    if (_faces.isEmpty) return;
    final selected = await showDialog<FaceDetectionRecord?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Cover Photo'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _faces.length,
            itemBuilder: (context, index) {
              final face = _faces[index];
              return GestureDetector(
                onTap: () => Navigator.pop(context, face),
                child: _FaceThumbnail(face: face),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      try {
        final peopleService = PeopleService(
          logger: _logger,
          database: _database,
        );
        await peopleService.setPersonCoverPhoto(
          widget.cluster.personId,
          selected.photoId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cover photo updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to set cover: $e')));
        }
      }
    }
  }

  // ─────────────────────────────────────────────
  // Delete
  // ─────────────────────────────────────────────

  Future<void> _deletePerson() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.cluster.label}?'),
        content: Text(
          'This will remove the person label from ${_faces.length} '
          '${_faces.length == 1 ? 'face' : 'faces'}. '
          'Photos will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final service = await ref.read(
          faceClusteringServiceProviderAsync.future,
        );
        if (!mounted) return;
        await service.deleteCluster(widget.cluster.label);
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }
}

// ─────────────────────────────────────────────
// Supporting Widgets
// ─────────────────────────────────────────────

/// Card widget for a person cluster in the grid.
class _PersonClusterCard extends StatelessWidget {
  const _PersonClusterCard({
    required this.cluster,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onMerge,
  });

  final PersonCluster cluster;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMerge;

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
            Expanded(
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
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cluster.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cluster.faceCount} ${cluster.faceCount == 1 ? 'face' : 'faces'} • ${cluster.photoCount} ${cluster.photoCount == 1 ? 'photo' : 'photos'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                onMerge();
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

/// Face thumbnail widget that loads the actual photo.
class _FaceThumbnail extends StatelessWidget {
  const _FaceThumbnail({
    required this.face,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  final FaceDetectionRecord face;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<AssetEntity?>(
            future: AssetEntity.fromId(face.photoId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData &&
                  snapshot.data != null) {
                return AssetEntityImage(
                  snapshot.data!,
                  isOriginal: false,
                  // Face tiles are small — 160px is plenty, 300px over-decodes.
                  thumbnailSize: const ThumbnailSize.square(160),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                );
              }
              return _buildPlaceholder(theme);
            },
          ),
          // Confidence badge
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(face.confidence * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
          // Selection overlay
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(80),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.face,
        size: 32,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
