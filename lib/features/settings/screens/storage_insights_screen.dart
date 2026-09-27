import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/di/providers.dart';
import '../../video_intelligence/services/video_resource_manager.dart';

/// Storage insights screen showing library size, video usage, cache, etc.
class StorageInsightsScreen extends ConsumerStatefulWidget {
  const StorageInsightsScreen({super.key});

  @override
  ConsumerState<StorageInsightsScreen> createState() =>
      _StorageInsightsScreenState();
}

class _StorageInsightsScreenState
    extends ConsumerState<StorageInsightsScreen> {
  bool _loading = true;
  int _photoCount = 0;
  int _videoCount = 0;
  int _totalAssetBytes = 0;
  int _favoritesCount = 0;
  int _editedCount = 0;
  String _processingState = 'Idle';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final db = ref.read(appDatabaseProvider).requireValue;

      // Count from device
      final paths = await PhotoManager.getAssetPathList(type: RequestType.all);
      for (final path in paths) {
        final count = await path.assetCountAsync;
        final assets = await path.getAssetListRange(start: 0, end: count);
        for (final asset in assets) {
          if (asset.type == AssetType.video) {
            _videoCount++;
          } else {
            _photoCount++;
          }
        }
      }

      // Count from database
      _favoritesCount = await db.database
          .rawQuery('SELECT COUNT(*) as cnt FROM favorites')
          .then((r) => r.first['cnt'] as int);
      _editedCount = await db.database
          .rawQuery('SELECT COUNT(*) as cnt FROM edit_recipes')
          .then((r) => r.first['cnt'] as int);

      // Check processing state
      final pendingJobs = await db.database
          .rawQuery("SELECT COUNT(*) as cnt FROM ai_jobs WHERE status = 'pending'")
          .then((r) => r.first['cnt'] as int);
      if (pendingJobs > 0) {
        _processingState = '$pendingJobs jobs pending';
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage Insights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Library overview
                _InsightCard(
                  title: 'Library Overview',
                  icon: Icons.photo_library_outlined,
                  children: [
                    _InsightRow(label: 'Photos', value: '$_photoCount'),
                    _InsightRow(label: 'Videos', value: '$_videoCount'),
                    _InsightRow(
                        label: 'Total',
                        value: '${_photoCount + _videoCount}',
                        bold: true),
                  ],
                ),
                const SizedBox(height: 12),

                // AI Status
                _InsightCard(
                  title: 'AI Processing',
                  icon: Icons.auto_awesome,
                  children: [
                    _InsightRow(label: 'Status', value: _processingState),
                  ],
                ),
                const SizedBox(height: 12),

                // Organization
                _InsightCard(
                  title: 'Organization',
                  icon: Icons.folder_outlined,
                  children: [
                    _InsightRow(label: 'Favorites', value: '$_favoritesCount'),
                    _InsightRow(label: 'Edited photos', value: '$_editedCount'),
                  ],
                ),
                const SizedBox(height: 12),

                // Privacy info
                _InsightCard(
                  title: 'Privacy',
                  icon: Icons.shield_outlined,
                  children: [
                    const _InsightRow(
                      label: 'Storage',
                      value: 'Local only',
                      valueColor: Colors.green,
                    ),
                    const _InsightRow(
                      label: 'AI processing',
                      value: 'On-device',
                      valueColor: Colors.green,
                    ),
                    const _InsightRow(
                      label: 'Data sharing',
                      value: 'None',
                      valueColor: Colors.green,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InsightCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _InsightRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
