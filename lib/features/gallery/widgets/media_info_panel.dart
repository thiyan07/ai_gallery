import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';

/// Enhanced media info panel that shows AI-derived insights.
///
/// Displays basic metadata + AI insights (people, objects, events, memories)
/// when available.
class MediaInfoPanel extends StatefulWidget {
  final AssetEntity asset;
  final AppDatabase database;

  const MediaInfoPanel({
    super.key,
    required this.asset,
    required this.database,
  });

  @override
  State<MediaInfoPanel> createState() => _MediaInfoPanelState();
}

class _MediaInfoPanelState extends State<MediaInfoPanel> {
  List<String> _people = [];
  List<String> _objects = [];
  String? _eventName;
  String? _ocrText;
  Map<String, String> _exif = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    try {
      final db = widget.database;
      final assetId = widget.asset.id;

      // People: named labels from face detections
      final faceRows = await db.database.rawQuery(
        'SELECT label FROM faces '
        'WHERE photo_id = ? AND label IS NOT NULL AND label != ""',
        [assetId],
      );
      _people = faceRows.map((r) => r['label'] as String).toSet().toList();

      // Objects with confidence
      final objectRows = await db.database.rawQuery(
        'SELECT DISTINCT label FROM object_tags '
        'WHERE photo_id = ? AND label IS NOT NULL AND label != ""',
        [assetId],
      );
      _objects = objectRows.map((r) => r['label'] as String).toList();

      // Event
      final eventRows = await db.database.rawQuery(
        'SELECT title FROM photo_events '
        'WHERE photo_ids LIKE ?',
        ['%$assetId%'],
      );
      if (eventRows.isNotEmpty) {
        _eventName = eventRows.first['title'] as String;
      }

      // OCR text
      final ocrRows = await db.database.rawQuery(
        'SELECT text FROM ocr_text WHERE photo_id = ? LIMIT 1',
        [assetId],
      );
      if (ocrRows.isNotEmpty) {
        _ocrText = ocrRows.first['text'] as String;
      }

      // Camera/file details from indexed metadata (Aves-style explorer)
      final meta = await db.photoMetadata.getById(assetId);
      if (meta != null) {
        final exif = <String, String>{};
        if ((meta.cameraMake ?? '').isNotEmpty) {
          exif['Camera'] = [meta.cameraMake, meta.cameraModel]
              .where((s) => (s ?? '').isNotEmpty)
              .join(' ');
        }
        if (meta.iso != null && meta.iso! > 0) exif['ISO'] = '${meta.iso}';
        if (meta.aperture != null && meta.aperture! > 0) {
          exif['Aperture'] = 'f/${meta.aperture!.toStringAsFixed(1)}';
        }
        if (meta.shutterSpeed != null && meta.shutterSpeed! > 0) {
          final s = meta.shutterSpeed!;
          exif['Shutter'] = s >= 1 ? '${s.toStringAsFixed(1)}s' : '1/${(1 / s).round()}s';
        }
        if (meta.fileSizeBytes > 0) exif['File size'] = _formatBytes(meta.fileSizeBytes);
        if ((meta.mimeType ?? '').isNotEmpty) exif['Format'] = meta.mimeType!;
        _exif = exif;
      }
    } catch (_) {
      // Silently fail — insights are optional
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Basic info ──
          Text(
            widget.asset.type == AssetType.video ? 'Video Details' : 'Photo Details',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _DetailRow(label: 'Filename', value: widget.asset.title ?? '—'),
          _DetailRow(
            label: 'Dimensions',
            value: '${widget.asset.width} × ${widget.asset.height}',
          ),
          _DetailRow(
            label: 'Type',
            value: widget.asset.type == AssetType.video ? 'Video' : 'Image',
          ),
          _DetailRow(
            label: 'Date taken',
            value: widget.asset.createDateTime.toLocal().toString().split('.')[0],
          ),
          if (widget.asset.type == AssetType.video)
            _DetailRow(
              label: 'Duration',
              value:
                  '${widget.asset.duration ~/ 60}:${(widget.asset.duration % 60).toString().padLeft(2, '0')}',
            ),
          if (widget.asset.latitude != null && widget.asset.longitude != null)
            _DetailRow(
              label: 'Location',
              value:
                  '${widget.asset.latitude!.toStringAsFixed(4)}, ${widget.asset.longitude!.toStringAsFixed(4)}',
            ),

          // ── Camera & file (from indexed EXIF) ──
          if (!_loading && _exif.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Camera & File',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final entry in _exif.entries)
              _DetailRow(label: entry.key, value: entry.value),
          ],

          // ── AI Insights ──
          if (!_loading) ...[
            if (_people.isNotEmpty ||
                _objects.isNotEmpty ||
                _eventName != null ||
                _ocrText != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI Insights',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // People
            if (_people.isNotEmpty) ...[
              _InsightSection(
                icon: Icons.people_outline,
                label: 'People',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _people
                      .map((p) => Chip(
                            label: Text(p, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Objects
            if (_objects.isNotEmpty) ...[
              _InsightSection(
                icon: Icons.category_outlined,
                label: 'Objects',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _objects
                      .map((o) => Chip(
                            label: Text(o, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Event
            if (_eventName != null) ...[
              _InsightSection(
                icon: Icons.event_outlined,
                label: 'Event',
                child: Text(
                  _eventName!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // OCR text
            if (_ocrText != null && _ocrText!.isNotEmpty) ...[
              _InsightSection(
                icon: Icons.text_fields,
                label: 'Text in image',
                child: Text(
                  _ocrText!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _InsightSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _InsightSection({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
      ],
    );
  }
}
