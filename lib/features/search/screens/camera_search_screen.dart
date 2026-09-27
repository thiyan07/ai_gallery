import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_gallery/core/di/providers.dart' hide searchServiceProvider;
import 'package:ai_gallery/core/widgets/shimmer_grid.dart';
import 'package:ai_gallery/features/gallery/providers/gallery_providers.dart';
import 'package:ai_gallery/features/gallery/screens/photo_view_screen.dart';
import 'package:ai_gallery/features/search/providers/search_providers.dart';
import 'package:ai_gallery/features/search/widgets/search_results_grid.dart';
import 'package:ai_gallery/features/settings/screens/local_models_screen.dart';

/// Point-and-search: capture a photo with the camera and find visually
/// similar photos in the library (concept from CLIP-Finder2, reimplemented
/// against this app's own embedding pipeline).
class CameraSearchScreen extends ConsumerStatefulWidget {
  const CameraSearchScreen({super.key});

  @override
  ConsumerState<CameraSearchScreen> createState() => _CameraSearchScreenState();
}

class _CameraSearchScreenState extends ConsumerState<CameraSearchScreen> {
  CameraController? _controller;
  String? _initError;
  bool _capturing = false;
  bool _searching = false;
  Uint8List? _capturedBytes;
  List<RankedSearchResult>? _results;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _initError = _cameraErrorMessage(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initError = 'Could not start the camera: $e');
      }
    }
  }

  static String _cameraErrorMessage(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'cameraAccessDenied':
        return 'Camera permission denied. Allow camera access to use visual search.';
      default:
        return 'Could not start the camera (${e.code}).';
    }
  }

  Future<void> _captureAndSearch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() {
      _capturing = true;
      _searchError = null;
    });
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _searching = true;
        _results = null;
      });
      final service = ref.read(searchServiceProvider);
      try {
        final results = await service.searchByImage(bytes, limit: 20);
        if (mounted) {
          setState(() {
            _results = results;
            _searching = false;
          });
        }
      } on StateError catch (e) {
        if (mounted) {
          setState(() {
            _searchError = e.toString();
            _searching = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = 'Capture failed: $e';
          _searching = false;
        });
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() {
    setState(() {
      _capturedBytes = null;
      _results = null;
      _searchError = null;
    });
  }

  Future<void> _openPhotoView(RankedSearchResult tapped) async {
    final photoRepo = ref.read(photoRepositoryProvider);
    final assets = await photoRepo.getAssetsByIds([tapped.photoId]);
    if (!mounted || assets.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(assets: assets, initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Camera search')),
      body: _buildBody(theme),
      floatingActionButton: _showCaptureButton
          ? FloatingActionButton.large(
              onPressed: _captureAndSearch,
              tooltip: 'Capture and search',
              child: _capturing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  bool get _showCaptureButton =>
      _controller != null && _capturedBytes == null && _initError == null;

  Widget _buildBody(ThemeData theme) {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 64),
              const SizedBox(height: 16),
              Text(_initError!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_capturedBytes != null) {
      return _buildResults(theme);
    }
    return CameraPreview(controller);
  }

  Widget _buildResults(ThemeData theme) {
    final gridSize = ref.watch(gridSizeProvider);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _capturedBytes!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _searching
                      ? 'Searching for similar photos…'
                      : '${_results?.length ?? 0} similar photos',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: _retake,
                icon: const Icon(Icons.refresh),
                label: const Text('Retake'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildResultsBody(theme, gridSize)),
      ],
    );
  }

  Widget _buildResultsBody(ThemeData theme, int gridSize) {
    if (_searching) {
      return ShimmerGrid(columns: gridSize.clamp(2, 6));
    }
    if (_searchError != null) {
      final isModelMissing = _searchError!.contains('MODEL_NOT_READY');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.psychology_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                isModelMissing
                    ? 'An embedding model is needed for visual search.'
                    : _searchError!,
                textAlign: TextAlign.center,
              ),
              if (isModelMissing) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Open AI Models'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LocalModelsScreen(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final results = _results ?? [];
    if (results.isEmpty) {
      return const Center(child: Text('No similar photos found.'));
    }
    return SearchResultsGrid(
      results: results,
      gridSize: gridSize,
      query: '',
      onTap: _openPhotoView,
    );
  }
}
