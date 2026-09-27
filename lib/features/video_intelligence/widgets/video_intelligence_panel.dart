import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/models/video_segment.dart';

/// Panel showing video intelligence insights below the player.
///
/// Shows chapters, highlights, and scene information when available.
class VideoIntelligencePanel extends StatefulWidget {
  final String videoId;
  final AppDatabase database;
  final void Function(Duration position)? onSeekTo;

  const VideoIntelligencePanel({
    super.key,
    required this.videoId,
    required this.database,
    this.onSeekTo,
  });

  @override
  State<VideoIntelligencePanel> createState() => _VideoIntelligencePanelState();
}

class _VideoIntelligencePanelState extends State<VideoIntelligencePanel> {
  List<VideoSegment> _segments = [];
  String? _ocrText;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _segments = await widget.database.videoSegments
          .getByVideoId(widget.videoId);

      final ocrRows = await widget.database.database.rawQuery(
        'SELECT ocr_text FROM video_segments '
        'WHERE video_id = ? AND ocr_text IS NOT NULL AND ocr_text != "" '
        'LIMIT 5',
        [widget.videoId],
      );
      if (ocrRows.isNotEmpty) {
        _ocrText = ocrRows.map((r) => r['ocr_text'] as String).join(' · ');
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_segments.isEmpty && _ocrText == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // People detected
          if (_segments.any((s) => s.people.isNotEmpty))
            _PeopleBar(segments: _segments),

          // Objects/scenes
          if (_segments.any((s) => s.labels.isNotEmpty))
            _SceneBar(segments: _segments, onSeekTo: widget.onSeekTo),

          // OCR text
          if (_ocrText != null && _ocrText!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.text_fields, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _ocrText!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PeopleBar extends StatelessWidget {
  final List<VideoSegment> segments;

  const _PeopleBar({required this.segments});

  @override
  Widget build(BuildContext context) {
    final people = <String>{};
    for (final seg in segments) {
      people.addAll(seg.people.where((p) => !p.startsWith('face:')));
    }
    if (people.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.people_outline, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: people.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(p,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white)),
                      backgroundColor: Colors.white24,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneBar extends StatelessWidget {
  final List<VideoSegment> segments;
  final void Function(Duration position)? onSeekTo;

  const _SceneBar({required this.segments, this.onSeekTo});

  @override
  Widget build(BuildContext context) {
    final labels = <String>{};
    for (final seg in segments) {
      labels.addAll(seg.labels);
    }
    if (labels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.category_outlined, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: labels.take(6).map((l) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(l,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70)),
                      backgroundColor: Colors.white12,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: onSeekTo != null
                          ? () {
                              final seg = segments.firstWhere(
                                (s) => s.labels.contains(l),
                                orElse: () => segments.first,
                              );
                              onSeekTo!(
                                  Duration(milliseconds: seg.startTimeMs));
                            }
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
