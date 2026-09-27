import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/features/video_intelligence/widgets/video_intelligence_panel.dart';

/// Full-screen video player with controls.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  final AssetEntity asset;
  final Duration? startAt;

  const VideoPlayerScreen({
    super.key,
    required this.asset,
    this.startAt,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = await widget.asset.originFile;
      if (file == null) {
        setState(() => _error = 'Could not load video file');
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      if (widget.startAt != null) {
        await _controller!.seekTo(widget.startAt!);
      }

      _controller!.addListener(_onPlayerUpdate);

      if (mounted) {
        setState(() => _isInitialized = true);
        _controller!.play();
      }
    } catch (e, st) {
      const ConsoleAppLogger().error('Video player init failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _error = 'Failed to initialize video: $e');
      }
    }
  }

  void _onPlayerUpdate() {
    if (mounted && _controller != null) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// Compute a safe video aspect ratio, falling back to 16:9 when the video
  /// size is unknown/zero (avoids AspectRatio throwing on NaN/0).
  double _safeAspectRatio() {
    final size = _controller?.value.size;
    if (size != null && size.width > 0 && size.height > 0 && size.isFinite) {
      final r = size.width / size.height;
      if (r.isFinite && r > 0) return r;
    }
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                widget.asset.title ?? 'Video',
                style: const TextStyle(fontSize: 16),
              ),
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Center(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    final rawAspect = _controller!.value.aspectRatio;
    // Some decoders/containers report a zero, NaN, or infinite aspect ratio
    // early on, which makes AspectRatio throw during build (black video, but
    // audio still plays). Guard with a sensible fallback.
    final aspectRatio = (rawAspect.isFinite && rawAspect > 0)
        ? rawAspect
        : _safeAspectRatio();

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        // Video intelligence insights (panel is omitted until the DB is ready,
        // so a slow/failed DB load never crashes video playback itself).
        if (ref.watch(appDatabaseProvider).hasValue)
          VideoIntelligencePanel(
            videoId: widget.asset.id,
            database: ref.watch(appDatabaseProvider).requireValue,
            onSeekTo: (position) {
              _controller?.seekTo(position);
            },
          ),
        if (_showControls) _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    final value = _controller!.value;
    final position = value.position;
    final duration = value.duration;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black87,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seek bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 2,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: position.inMilliseconds.toDouble().clamp(
                  0,
                  duration.inMilliseconds.toDouble(),
                ),
                max: duration.inMilliseconds.toDouble(),
                onChanged: (v) {
                  _controller!.seekTo(Duration(milliseconds: v.toInt()));
                },
              ),
            ),
            // Time labels and play/pause
            Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () {
                    if (value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                // Duration badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
