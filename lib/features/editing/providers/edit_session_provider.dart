import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import '../../../core/di/providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_history.dart';
import '../../../domain/models/edit/edit_operation.dart';
import '../../../domain/models/edit/edit_recipe.dart';
import '../../../domain/models/edit/drawing_layer.dart';
import '../../../domain/models/edit/text_layer.dart';
import '../../../domain/models/edit/frame_config.dart';
import '../services/edit_export_service.dart';
import '../services/edit_transformation_engine.dart';

/// State of the photo editing session for a single photo.
class EditSessionState {
  final String photoId;
  final EditRecipe recipe;
  final bool isLoading;
  final bool isSaving;
  final int originalWidth;
  final int originalHeight;
  final String? error;
  final bool isCropMode;
  final bool isRotateMode;
  final bool isStraightenMode;
  final bool isAdjustMode;
  final bool isFilterMode;
  final bool isEffectsMode;
  final bool isDrawMode;
  final bool isTextMode;
  final bool isFrameMode;
  final bool isCurvesMode;
  final bool isHslMode;
  final bool isPromptMode;
  final double straightenDegrees;
  final bool isFlippedH;
  final bool isFlippedV;
  final CropRect currentCrop;

  const EditSessionState({
    required this.photoId,
    required this.recipe,
    this.isLoading = false,
    this.isSaving = false,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.error,
    this.isCropMode = false,
    this.isRotateMode = false,
    this.isStraightenMode = false,
    this.isAdjustMode = false,
    this.isFilterMode = false,
    this.isEffectsMode = false,
    this.isDrawMode = false,
    this.isTextMode = false,
    this.isFrameMode = false,
    this.isCurvesMode = false,
    this.isHslMode = false,
    this.isPromptMode = false,
    this.straightenDegrees = 0,
    this.isFlippedH = false,
    this.isFlippedV = false,
    this.currentCrop = const CropRect(left: 0, top: 0, width: 1, height: 1),
  });

  bool get hasEdits => recipe.isNotEmpty;

  /// Get a specific adjustment value from the recipe.
  double adjustmentValue(String name) => recipe.adjustmentValue(name);

  /// Whether there are any active adjustments.
  bool get hasAdjustments => recipe.hasAdjustments;

  EditSessionState copyWith({
    String? photoId,
    EditRecipe? recipe,
    bool? isLoading,
    bool? isSaving,
    int? originalWidth,
    int? originalHeight,
    String? error,
    bool? isCropMode,
    bool? isRotateMode,
    bool? isStraightenMode,
    bool? isAdjustMode,
    bool? isFilterMode,
    bool? isEffectsMode,
    bool? isDrawMode,
    bool? isTextMode,
    bool? isFrameMode,
    bool? isCurvesMode,
    bool? isHslMode,
    bool? isPromptMode,
    double? straightenDegrees,
    bool? isFlippedH,
    bool? isFlippedV,
    CropRect? currentCrop,
  }) {
    return EditSessionState(
      photoId: photoId ?? this.photoId,
      recipe: recipe ?? this.recipe,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      originalWidth: originalWidth ?? this.originalWidth,
      originalHeight: originalHeight ?? this.originalHeight,
      error: error,
      isCropMode: isCropMode ?? this.isCropMode,
      isRotateMode: isRotateMode ?? this.isRotateMode,
      isStraightenMode: isStraightenMode ?? this.isStraightenMode,
      isAdjustMode: isAdjustMode ?? this.isAdjustMode,
      isFilterMode: isFilterMode ?? this.isFilterMode,
      isEffectsMode: isEffectsMode ?? this.isEffectsMode,
      isDrawMode: isDrawMode ?? this.isDrawMode,
      isTextMode: isTextMode ?? this.isTextMode,
      isFrameMode: isFrameMode ?? this.isFrameMode,
      isCurvesMode: isCurvesMode ?? this.isCurvesMode,
      isHslMode: isHslMode ?? this.isHslMode,
      isPromptMode: isPromptMode ?? this.isPromptMode,
      straightenDegrees: straightenDegrees ?? this.straightenDegrees,
      isFlippedH: isFlippedH ?? this.isFlippedH,
      isFlippedV: isFlippedV ?? this.isFlippedV,
      currentCrop: currentCrop ?? this.currentCrop,
    );
  }
}

/// Holds the decoded image data for the editing session.
class EditImageData {
  final img.Image original;
  final img.Image preview;
  final EditHistoryManager history;

  EditImageData({
    required this.original,
    required this.preview,
    required this.history,
  });
}

/// Top-level function for reading file bytes in an isolate.
Uint8List __readFileBytes(String path) => File(path).readAsBytesSync();

/// Manages the edit session for a single photo using ChangeNotifier.
///
/// This allows the session to hold non-serializable state (img.Image)
/// that cannot be represented through standard Riverpod state.
class EditSessionController extends ChangeNotifier {
  EditSessionController(this._ref, this._photoId)
      : _state = EditSessionState(
          photoId: _photoId,
          recipe: EditRecipe(
            photoId: _photoId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          isLoading: true,
        ) {
    _loadPhoto(_photoId);
  }

  final Ref _ref;
  final String _photoId;
  EditImageData? _imageData;
  EditSessionState _state;
  EditCancelToken? _cancelToken;

  EditSessionState get state => _state;
  bool get canUndo => _imageData?.history.canUndo ?? false;
  bool get canRedo => _imageData?.history.canRedo ?? false;
  img.Image? get originalImage => _imageData?.original;
  img.Image? get previewImage => _imageData?.preview;

  Future<void> _loadPhoto(String photoId) async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final existing = await db.editRecipes.getByPhotoId(photoId);

      final asset = await AssetEntity.fromId(photoId);
      if (asset == null) {
        _state = _state.copyWith(isLoading: false, error: 'Photo not found');
        notifyListeners();
        return;
      }

      final file = await asset.originFile;
      if (file == null) {
        _state = _state.copyWith(
          isLoading: false,
          error: 'Could not load photo file',
        );
        notifyListeners();
        return;
      }

      // Decode image off UI thread to avoid jank on large photos
      final filePath = file.path;
      final decoded = await Isolate.run(() {
        final bytes = __readFileBytes(filePath);
        return img.decodeImage(bytes);
      });

      if (decoded == null) {
        _state = _state.copyWith(
          isLoading: false,
          error: 'Could not decode photo',
        );
        notifyListeners();
        return;
      }

      final preview = EditTransformationEngine.createPreview(decoded);

      final recipe = existing ??
          EditRecipe(
            photoId: photoId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

      final history = EditHistoryManager(initial: recipe);

      _imageData = EditImageData(
        original: decoded,
        preview: preview,
        history: history,
      );

      _state = _state.copyWith(
        isLoading: false,
        originalWidth: decoded.width,
        originalHeight: decoded.height,
        recipe: recipe,
        currentCrop: recipe.effectiveCrop,
        isFlippedH: recipe.isFlippedHorizontally,
        isFlippedV: recipe.isFlippedVertically,
        straightenDegrees: recipe.operations
            .where((op) => op.type == EditOperationType.straighten)
            .fold<double>(0.0, (sum, op) => sum + op.degrees),
      );
      notifyListeners();

      if (recipe.isNotEmpty) {
        _updatePreview();
      }
    } catch (e, st) {
      _ref.read(appLoggerProvider).error(
        'Failed to load photo for editing',
        error: e,
        stackTrace: st,
      );
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to load photo: $e',
      );
      notifyListeners();
    }
  }

  // ==========================================================================
  // GEOMETRIC EDIT ACTIONS
  // ==========================================================================

  void applyCrop({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final ops = List<EditOperation>.from(_state.recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.crop)
      ..add(EditOperation.crop(
        left: left,
        top: top,
        width: width,
        height: height,
      ));
    _updateRecipe(ops, discrete: true);
  }

  void applyRotation(double degrees) {
    final ops = List<EditOperation>.from(_state.recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.rotate)
      ..add(EditOperation.rotate(degrees: degrees));
    _updateRecipe(ops, discrete: true);
  }

  void cycleRotation() {
    final current = _state.recipe.effectiveRotation;
    final next = (current + 90) % 360;
    applyRotation(next);
  }

  void toggleHorizontalFlip() {
    _updateFlip(!_state.isFlippedH, _state.isFlippedV);
  }

  void toggleVerticalFlip() {
    _updateFlip(_state.isFlippedH, !_state.isFlippedV);
  }

  void _updateFlip(bool h, bool v) {
    final ops = List<EditOperation>.from(_state.recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.flip);
    if (h || v) {
      ops.add(EditOperation.flip(horizontal: h, vertical: v));
    }
    _state = _state.copyWith(isFlippedH: h, isFlippedV: v);
    _updateRecipe(ops, discrete: true);
  }

  void setStraighten(double degrees) {
    final clamped = degrees.clamp(-45.0, 45.0);
    final ops = List<EditOperation>.from(_state.recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.straighten);
    if (clamped != 0) {
      ops.add(EditOperation.straighten(degrees: clamped));
    }
    _state = _state.copyWith(straightenDegrees: clamped);
    _updateRecipe(ops, discrete: false);
  }

  // Phase 14: Resize & Perspective
  void setResize({required int width, required int height, bool maintainAspect = true}) {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.resize);
    ops.add(EditOperation.resize(width: width, height: height, maintainAspect: maintainAspect));
    _updateRecipe(ops, discrete: true);
  }
  void removeResize() {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.resize);
    _updateRecipe(ops, discrete: true);
  }
  void setPerspective({double tlX=0,double tlY=0,double trX=0,double trY=0,double brX=0,double brY=0,double blX=0,double blY=0}) {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.perspective);
    final op = EditOperation.perspective(tlX: tlX, tlY: tlY, trX: trX, trY: trY, brX: brX, brY: brY, blX: blX, blY: blY);
    if (!op.isNoOp) ops.add(op);
    _updateRecipe(ops, discrete: true);
  }
  void removePerspective() {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.perspective);
    _updateRecipe(ops, discrete: true);
  }

  // Phase 15: Enhancement / Upscaling / Denoising / Auto-enhance
  void setEnhancement({double strength = 0.5, bool auto = true}) {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.enhancement);
    final op = EditOperation.enhancement(strength: strength, auto: auto);
    if (!op.isNoOp) ops.add(op);
    _updateRecipe(ops, discrete: true);
  }
  void removeEnhancement() {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.enhancement);
    _updateRecipe(ops, discrete: true);
  }
  void setUpscaling({int scale = 2, String? modelId}) {
    final s = scale.clamp(2, 4);
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.upscaling);
    ops.add(EditOperation.upscaling(scale: s == 3 ? 2 : s, modelId: modelId));
    _updateRecipe(ops, discrete: true);
  }
  void removeUpscaling() {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.upscaling);
    _updateRecipe(ops, discrete: true);
  }
  void setDenoising({double strength = 0.5, String method = 'bilateral'}) {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.denoising);
    final op = EditOperation.denoising(strength: strength, method: method);
    if (!op.isNoOp) ops.add(op);
    _updateRecipe(ops, discrete: true);
  }
  void removeDenoising() {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.denoising);
    _updateRecipe(ops, discrete: true);
  }
  void setAutoEnhance(Map<String, double> adjustments) {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.autoEnhance);
    ops.add(EditOperation.autoEnhance(adjustments: adjustments));
    _updateRecipe(ops, discrete: true);
  }
  void removeAutoEnhance() {
    final ops = List<EditOperation>.from(_state.recipe.operations)..removeWhere((op) => op.type == EditOperationType.autoEnhance);
    _updateRecipe(ops, discrete: true);
  }

  // ==========================================================================
  // ADJUSTMENT ACTIONS
  // ==========================================================================

  /// Update a single adjustment value during slider interaction.
  /// Uses replaceCurrent (no new undo entry) for responsive preview.
  void setAdjustment(String name, double value) {
    final newRecipe = _state.recipe.withAdjustment(name, value);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.replaceCurrent(newRecipe.operations);
    _updatePreview();
  }

  /// Commit the current adjustment state as a new undo entry.
  /// Call when the slider is released.
  void commitAdjustment() {
    if (_imageData != null) {
      _imageData!.history.commitState(_state.recipe.operations);
    }
  }

  /// Reset a single adjustment to neutral.
  void resetAdjustment(String name) {
    final newRecipe = _state.recipe.resetAdjustment(name);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.coalesceState(newRecipe.operations);
    _updatePreview();
  }

  // ==========================================================================
  // CREATIVE OPERATION ACTIONS
  // ==========================================================================

  /// Set or update the filter.
  void setFilter(String presetId, double intensity) {
    final newRecipe = _state.recipe.withFilter(presetId, intensity);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Update filter intensity during slider interaction (live preview).
  void setFilterIntensity(double intensity) {
    final filterOp = _state.recipe.filterOperation;
    if (filterOp == null) return;
    final newOp = filterOp.filterWithIntensity(intensity);
    final newOps = List<EditOperation>.from(_state.recipe.operations);
    final idx = newOps.indexWhere((op) => op.type == EditOperationType.filter);
    if (idx >= 0) newOps[idx] = newOp;
    final newRecipe = _state.recipe.copyWith(operations: newOps);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.replaceCurrent(newRecipe.operations);
    _updatePreview();
  }

  /// Commit filter intensity change.
  void commitFilter() {
    if (_imageData != null) {
      _imageData!.history.commitState(_state.recipe.operations);
    }
  }

  /// Remove the filter.
  void removeFilter() {
    final newRecipe = _state.recipe.withoutFilter();
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Set blur effect.
  void setBlur(double radius, double strength) {
    final newRecipe = _state.recipe.withBlur(radius, strength);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Set grain effect.
  void setGrain(double intensity, double size) {
    final newRecipe = _state.recipe.withGrain(intensity, size);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Set fade effect.
  void setFade(double intensity) {
    final newRecipe = _state.recipe.withFade(intensity);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Set the drawing layer.
  void setDrawing(DrawingLayer layer) {
    final newRecipe = _state.recipe.withDrawing(layer);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Update drawing during live interaction (no new undo entry).
  void updateDrawing(DrawingLayer layer) {
    final newRecipe = _state.recipe.withDrawing(layer);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.replaceCurrent(newRecipe.operations);
    _updatePreview();
  }

  /// Commit drawing state as a new undo entry.
  void commitDrawing() {
    if (_imageData != null) {
      _imageData!.history.commitState(_state.recipe.operations);
    }
  }

  /// Set text layers.
  void setTextLayers(List<TextLayer> layers) {
    final newRecipe = _state.recipe.withTextLayers(layers);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Set frame configuration.
  void setFrame(FrameConfig config) {
    final newRecipe = _state.recipe.withFrame(config);
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  /// Remove frame.
  void removeFrame() {
    final newRecipe = _state.recipe.withoutFrame();
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.pushState(newRecipe.operations);
    _updatePreview();
  }

  // ==========================================================================
  // ADVANCED COLOR ACTIONS (Phase 29)
  // ==========================================================================

  /// Replace the entire recipe (used by curves/HSL panels for direct manipulation).
  void replaceRecipe(EditRecipe newRecipe) {
    _state = _state.copyWith(recipe: newRecipe);
    _imageData?.history.replaceCurrent(newRecipe.operations);
    _updatePreview();
  }

  /// Apply a list of operations as a single discrete undo entry.
  /// Used by EditPlanPanel for batch application of AI-suggested edits.
  void applyOperations(List<EditOperation> operations) {
    final currentOps = List<EditOperation>.from(_state.recipe.operations);
    final newOps = [...currentOps, ...operations];
    _updateRecipe(newOps, discrete: true);
  }

  // ==========================================================================
  // MODE TOGGLES
  // ==========================================================================

  void enterAdjustMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: true,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterCropMode() {
    _state = _state.copyWith(
      isCropMode: true,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterRotateMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: true,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterStraightenMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: true,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterFilterMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: true,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterEffectsMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: true,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterDrawMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: true,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterTextMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: true,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterFrameMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: true,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterCurvesMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: true,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterHslMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: true,
      isPromptMode: false,
    );
    notifyListeners();
  }

  void enterPromptMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: true,
    );
    notifyListeners();
  }

  void exitEditMode() {
    _state = _state.copyWith(
      isCropMode: false,
      isRotateMode: false,
      isStraightenMode: false,
      isAdjustMode: false,
      isFilterMode: false,
      isEffectsMode: false,
      isDrawMode: false,
      isTextMode: false,
      isFrameMode: false,
      isCurvesMode: false,
      isHslMode: false,
      isPromptMode: false,
    );
    notifyListeners();
  }

  // ==========================================================================
  // UNDO / REDO
  // ==========================================================================

  void undo() {
    final ops = _imageData?.history.undo();
    if (ops != null) {
      _updateRecipeFromHistory(List.from(ops));
    }
  }

  void redo() {
    final ops = _imageData?.history.redo();
    if (ops != null) {
      _updateRecipeFromHistory(List.from(ops));
    }
  }

  void resetAll() {
    _imageData?.history.reset();
    final recipe = EditRecipe(
      photoId: _photoId,
      createdAt: _state.recipe.createdAt,
      updatedAt: DateTime.now(),
    );
    _state = _state.copyWith(
      recipe: recipe,
      currentCrop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      isFlippedH: false,
      isFlippedV: false,
      straightenDegrees: 0,
    );
    _updatePreview();
  }

  // ==========================================================================
  // SAVE / EXPORT
  // ==========================================================================

  void cancelExport() {
    _cancelToken?.cancel();
    _state = _state.copyWith(isSaving: false);
    notifyListeners();
  }

  Future<bool> saveRecipe() async {
    _cancelToken = EditCancelToken();
    _state = _state.copyWith(isSaving: true);
    notifyListeners();

    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final logger = _ref.read(appLoggerProvider);
      final recipe = _state.recipe.copyWith(updatedAt: DateTime.now());

      if (recipe.isNotEmpty && _imageData != null) {
        // Full export: apply recipe at full resolution and write to disk
        final exportService = EditExportService(logger: logger);
        final exportedPath = await exportService.exportPhoto(
          photoId: _photoId,
          recipe: recipe,
          cancelToken: _cancelToken,
        );

        if (_cancelToken?.isCancelled == true) {
          _state = _state.copyWith(isSaving: false);
          notifyListeners();
          return false;
        }

        // Update recipe with export info
        final exportedRecipe = recipe.copyWith(
          isExported: true,
          exportedPath: exportedPath,
        );
        await db.editRecipes.upsert(exportedRecipe);
        _state = _state.copyWith(recipe: exportedRecipe, isSaving: false);
      } else {
        // No edits — save recipe only (or delete if empty)
        await db.editRecipes.upsert(recipe);
        _state = _state.copyWith(recipe: recipe, isSaving: false);
      }

      notifyListeners();
      return true;
    } catch (e, st) {
      _ref.read(appLoggerProvider).error(
        'Failed to save edit recipe',
        error: e,
        stackTrace: st,
      );
      _state = _state.copyWith(
        isSaving: false,
        error: 'Failed to save: $e',
      );
      notifyListeners();
      return false;
    }
  }

  // ==========================================================================
  // INTERNAL UPDATE METHODS
  // ==========================================================================

  void _updateRecipe(List<EditOperation> ops, {required bool discrete}) {
    final recipe = _state.recipe.copyWith(
      operations: ops,
      updatedAt: DateTime.now(),
    );
    if (discrete) {
      _imageData?.history.pushState(ops);
    } else {
      _imageData?.history.coalesceState(ops);
    }
    _state = _state.copyWith(
      recipe: recipe,
      currentCrop: recipe.effectiveCrop,
    );
    _updatePreview();
  }

  void _updateRecipeFromHistory(List<EditOperation> ops) {
    final recipe = _state.recipe.copyWith(
      operations: ops,
      updatedAt: DateTime.now(),
    );
    _state = _state.copyWith(
      recipe: recipe,
      currentCrop: recipe.effectiveCrop,
      isFlippedH: recipe.isFlippedHorizontally,
      isFlippedV: recipe.isFlippedVertically,
      straightenDegrees: ops
          .where((op) => op.type == EditOperationType.straighten)
          .fold<double>(0.0, (sum, op) => sum + op.degrees),
    );
    _updatePreview();
  }

  void _updatePreview() {
    if (_imageData == null) return;
    final result = EditTransformationEngine.apply(
      _imageData!.original,
      _state.recipe,
    );
    final preview = EditTransformationEngine.createPreview(result.image);
    _imageData = EditImageData(
      original: _imageData!.original,
      preview: preview,
      history: _imageData!.history,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _imageData = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    super.dispose();
  }
}

/// Provider factory for the edit session controller.
///
/// Usage: `ref.watch(editSessionProvider('assetId123'))`
/// Returns an [EditSessionController] for that photo.
final editSessionProvider =
    Provider.autoDispose.family<EditSessionController, String>((ref, photoId) {
  final controller = EditSessionController(ref, photoId);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Whether the photo has any saved edit recipes.
final photoHasEditsProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, photoId) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return db.editRecipes.hasRecipe(photoId);
});
