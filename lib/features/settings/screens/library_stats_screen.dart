import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_gallery/core/di/providers.dart';

/// Library statistics: totals, formats, top objects/people, AI coverage.
/// (Aves-grade stats page, computed from the existing index tables.)
class LibraryStatsScreen extends ConsumerWidget {
  const LibraryStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library stats')),
      body: FutureBuilder<LibraryStats>(
        future: _loadStats(ref),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data;
          if (stats == null) {
            return const Center(child: Text('Could not load stats.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: 'Library',
                rows: [
                  _Row(label: 'Photos indexed', value: '${stats.photos}'),
                  _Row(label: 'Videos indexed', value: '${stats.videos}'),
                  _Row(
                      label: 'Total size',
                      value: _formatBytes(stats.totalBytes)),
                  _Row(
                      label: 'Favorites', value: '${stats.favorites}'),
                  _Row(label: 'In trash', value: '${stats.trashed}'),
                ],
              ),
              _Section(
                title: 'People & faces',
                rows: [
                  _Row(label: 'People', value: '${stats.people}'),
                  _Row(label: 'Faces detected', value: '${stats.faces}'),
                ],
              ),
              _Section(
                title: 'AI index coverage',
                rows: [
                  _Row(
                      label: 'With embeddings',
                      value: '${stats.embeddedPhotos}'),
                  _Row(label: 'With OCR text', value: '${stats.ocrPhotos}'),
                ],
              ),
              if (stats.topObjects.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'Top detected objects',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final entry in stats.topObjects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key),
                            Text('${entry.value}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: stats.topObjects.first.value == 0
                              ? 0
                              : entry.value /
                                  stats.topObjects.first.value,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<LibraryStats> _loadStats(WidgetRef ref) async {
    final db = await ref.read(appDatabaseProvider.future);
    final photosRow = await db.database.rawQuery(
      "SELECT COUNT(*) as cnt, COALESCE(SUM(file_size_bytes),0) as bytes "
      "FROM photo_metadata WHERE media_type IS NULL OR media_type != 'video'",
    );
    final videosRow = await db.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM photo_metadata WHERE media_type = 'video'",
    );
    final favRow = await db.database
        .rawQuery('SELECT COUNT(*) as cnt FROM favorites');
    final trashRow =
        await db.database.rawQuery('SELECT COUNT(*) as cnt FROM trash');
    final peopleRow = await db.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM people WHERE status = 'active'",
    );
    final facesRow =
        await db.database.rawQuery('SELECT COUNT(*) as cnt FROM faces');
    final embRow = await db.database.rawQuery(
      'SELECT COUNT(DISTINCT photo_id) as cnt FROM embeddings',
    );
    final ocrRow = await db.database.rawQuery(
      'SELECT COUNT(DISTINCT photo_id) as cnt FROM ocr_text',
    );
    final topObjects = await db.objectTags.getTopLabels(limit: 10);

    int count(List<Map<String, Object?>> rows) =>
        (rows.first['cnt'] as int?) ?? 0;

    return LibraryStats(
      photos: count(photosRow),
      videos: count(videosRow),
      totalBytes: (photosRow.first['bytes'] as int?) ?? 0,
      favorites: count(favRow),
      trashed: count(trashRow),
      people: count(peopleRow),
      faces: count(facesRow),
      embeddedPhotos: count(embRow),
      ocrPhotos: count(ocrRow),
      topObjects: topObjects.entries.toList(),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class LibraryStats {
  const LibraryStats({
    required this.photos,
    required this.videos,
    required this.totalBytes,
    required this.favorites,
    required this.trashed,
    required this.people,
    required this.faces,
    required this.embeddedPhotos,
    required this.ocrPhotos,
    required this.topObjects,
  });

  final int photos;
  final int videos;
  final int totalBytes;
  final int favorites;
  final int trashed;
  final int people;
  final int faces;
  final int embeddedPhotos;
  final int ocrPhotos;
  final List<MapEntry<String, int>> topObjects;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
