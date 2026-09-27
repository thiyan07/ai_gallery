import 'dart:convert';

import 'edit_operation.dart';
import 'drawing_layer.dart';
import 'text_layer.dart';
import 'frame_config.dart';

/// A non-destructive edit recipe for a single photo.
///
/// Recipes are serializable (stored as JSON in the database) and versionable.
/// The operations list defines the full edit pipeline. Undo/redo is managed
/// by maintaining snapshots of the operations list.
///
/// Design principles:
/// - Original photo is never modified. Exported files are written to a
///   separate edited-images directory.
/// - Operations are applied in order (rendering pipeline order).
/// - The recipe can represent any combination of crop, rotate, flip,
///   straighten, and adjustments.
class EditRecipe {
  /// The photo this recipe applies to (AssetEntity.id).
  final String photoId;

  /// Ordered list of edit operations (applied in pipeline order).
  final List<EditOperation> operations;

  /// When this recipe was first created.
  final DateTime createdAt;

  /// When this recipe was last modified.
  final DateTime updatedAt;

  /// Schema version for forward-compatible deserialization.
  final int version;

  /// Whether the recipe has been exported to disk (edited file exists).
  final bool isExported;

  /// Path to the exported edited image file (null if not yet exported).
  final String? exportedPath;

  const EditRecipe({
    required this.photoId,
    this.operations = const [],
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.isExported = false,
    this.exportedPath,
  });

  /// Whether the recipe has any meaningful edits.
  bool get isEmpty =>
      operations.isEmpty || operations.every((op) => op.isNoOp);

  bool get isNotEmpty => !isEmpty;

  /// The adjustment operation from the operations list, or null.
  EditOperation? get adjustmentOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.adjustment) return op;
    }
    return null;
  }

  /// Whether this recipe has any non-neutral adjustments.
  bool get hasAdjustments {
    final adj = adjustmentOperation;
    return adj != null && adj.hasNonNeutralAdjustments;
  }

  /// Get a specific adjustment value by name.
  double adjustmentValue(String name) {
    return adjustmentOperation?.adjustmentValue(name) ?? 0.0;
  }

  /// Get all adjustment values as a map.
  Map<String, double> get adjustmentValues =>
      adjustmentOperation?.adjustmentValues ??
      Map<String, double>.from(AdjustmentDefaults.all);

  /// Whether any adjustment value is non-neutral.
  bool get hasNonNeutralAdjustments =>
      adjustmentOperation?.hasNonNeutralAdjustments ?? false;

  // ==========================================================================
  // CREATIVE OPERATION ACCESSORS
  // ==========================================================================

  /// The filter operation, or null.
  EditOperation? get filterOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.filter) return op;
    }
    return null;
  }

  /// Whether a filter is active.
  bool get hasFilter =>
      filterOperation != null && !(filterOperation!.isNoOp);

  /// The blur effect operation, or null.
  EditOperation? get blurOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.blur) return op;
    }
    return null;
  }

  /// The grain effect operation, or null.
  EditOperation? get grainOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.grain) return op;
    }
    return null;
  }

  /// The fade effect operation, or null.
  EditOperation? get fadeOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.fade) return op;
    }
    return null;
  }

  /// Whether any effects are active.
  bool get hasEffects =>
      (blurOperation != null && !(blurOperation!.isNoOp)) ||
      (grainOperation != null && !(grainOperation!.isNoOp)) ||
      (fadeOperation != null && !(fadeOperation!.isNoOp));

  /// The drawing operation, or null.
  EditOperation? get drawingOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.drawing) return op;
    }
    return null;
  }

  /// Parsed drawing layer, or empty.
  DrawingLayer get drawingLayer {
    final op = drawingOperation;
    if (op == null) return const DrawingLayer();
    return DrawingLayer.fromMap({'strokes': op.drawingStrokes});
  }

  /// Whether any drawing exists.
  bool get hasDrawing =>
      drawingOperation != null && !(drawingOperation!.isNoOp);

  /// The text operation, or null.
  EditOperation? get textOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.text) return op;
    }
    return null;
  }

  /// Parsed text layers, or empty.
  List<TextLayer> get textLayers {
    final op = textOperation;
    if (op == null) return [];
    return op.textLayers
        .map((m) => TextLayer.fromMap(m))
        .toList();
  }

  /// Whether any text layers exist.
  bool get hasText =>
      textOperation != null && !(textOperation!.isNoOp);

  /// The frame operation, or null.
  EditOperation? get frameOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.frame) return op;
    }
    return null;
  }

  /// Parsed frame config, or empty.
  FrameConfig get frameConfig {
    final op = frameOperation;
    if (op == null) return const FrameConfig();
    return FrameConfig(
      width: op.frameWidth,
      color: op.frameColor,
      opacity: op.frameOpacity,
      cornerRadius: (op.params['cornerRadius'] as num?)?.toDouble() ?? 0.0,
      roundedCorners: op.params['roundedCorners'] as bool? ?? false,
      imageCornerRadius: (op.params['imageCornerRadius'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Whether a frame is active.
  bool get hasFrame =>
      frameOperation != null && !(frameOperation!.isNoOp);

  /// Whether any creative edits exist.
  bool get hasCreativeEdits =>
      hasFilter || hasEffects || hasDrawing || hasText || hasFrame;

  // ==========================================================================
  // AI OPERATION ACCESSORS (Phase 21)
  // ==========================================================================

  /// Whether this recipe has any AI-powered operations.
  bool get hasAiEdits => operations.any((op) => op.isCreative && !op.isMetadataOnly);

  /// The background removal operation, or null.
  EditOperation? get backgroundRemovalOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.backgroundRemoval) return op;
    }
    return null;
  }

  /// Whether background removal is active.
  bool get hasBackgroundRemoval =>
      backgroundRemovalOperation != null && !(backgroundRemovalOperation!.isNoOp);

  /// The background replacement operation, or null.
  EditOperation? get backgroundReplacementOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.backgroundReplacement) return op;
    }
    return null;
  }

  /// Whether background replacement is active.
  bool get hasBackgroundReplacement =>
      backgroundReplacementOperation != null &&
      !(backgroundReplacementOperation!.isNoOp);

  /// The object removal operation, or null.
  EditOperation? get objectRemovalOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.objectRemoval) return op;
    }
    return null;
  }

  /// Whether object removal is active.
  bool get hasObjectRemoval =>
      objectRemovalOperation != null && !(objectRemovalOperation!.isNoOp);

  /// The inpainting operation, or null.
  EditOperation? get inpaintingOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.inpainting) return op;
    }
    return null;
  }

  /// Whether inpainting is active.
  bool get hasInpainting =>
      inpaintingOperation != null && !(inpaintingOperation!.isNoOp);

  /// The enhancement operation, or null.
  EditOperation? get enhancementOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.enhancement) return op;
    }
    return null;
  }

  /// Whether enhancement is active.
  bool get hasEnhancement =>
      enhancementOperation != null && !(enhancementOperation!.isNoOp);

  /// The upscaling operation, or null.
  EditOperation? get upscalingOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.upscaling) return op;
    }
    return null;
  }

  /// Whether upscaling is active.
  bool get hasUpscaling =>
      upscalingOperation != null && !(upscalingOperation!.isNoOp);

  /// The denoising operation, or null.
  EditOperation? get denoisingOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.denoising) return op;
    }
    return null;
  }

  /// Whether denoising is active.
  bool get hasDenoising =>
      denoisingOperation != null && !(denoisingOperation!.isNoOp);

  /// The smart crop operation, or null.
  EditOperation? get smartCropOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.smartCrop) return op;
    }
    return null;
  }

  /// The auto-enhance operation, or null.
  EditOperation? get autoEnhanceOperation {
    for (final op in operations) {
      if (op.type == EditOperationType.autoEnhance) return op;
    }
    return null;
  }

  /// Whether auto-enhance is active.
  bool get hasAutoEnhance =>
      autoEnhanceOperation != null && !(autoEnhanceOperation!.isNoOp);

  /// All operations that reference a mask (for mask dependency tracking).
  List<EditOperation> get maskDependentOperations =>
      operations.where((op) => op.usesMask).toList();

  /// All mask IDs referenced by this recipe.
  Set<String> get referencedMaskIds {
    final ids = <String>{};
    for (final op in operations) {
      final mid = op.maskId;
      if (mid != null) ids.add(mid);
    }
    return ids;
  }

  /// All AI operation summaries (for UI display).
  List<String> get aiOperationSummaries =>
      operations.where((op) => op.isCreative && !op.isMetadataOnly).map((op) => op.aiSummary).toList();

  /// Create a new recipe with a specific adjustment value changed.
  EditRecipe withAdjustment(String name, double value) {
    final current = adjustmentOperation;
    EditOperation newAdj;

    if (current != null) {
      newAdj = current.adjustmentWith(name, value);
    } else {
      // Create new adjustment operation with the specified value
      final params = <String, double>{
        for (final key in AdjustmentDefaults.all.keys) key: 0.0,
      };
      params[name] = value;
      newAdj = EditOperation.adjustment(
        exposure: params['exposure']!,
        brightness: params['brightness']!,
        contrast: params['contrast']!,
        highlights: params['highlights']!,
        shadows: params['shadows']!,
        whites: params['whites']!,
        blacks: params['blacks']!,
        saturation: params['saturation']!,
        vibrance: params['vibrance']!,
        temperature: params['temperature']!,
        tint: params['tint']!,
        sharpness: params['sharpness']!,
        clarity: params['clarity']!,
        vignette: params['vignette']!,
      );
    }

    // Replace existing adjustment op or append
    final newOps = List<EditOperation>.from(operations);
    final existingIdx = newOps.indexWhere(
      (op) => op.type == EditOperationType.adjustment,
    );
    if (existingIdx >= 0) {
      newOps[existingIdx] = newAdj;
    } else {
      newOps.add(newAdj);
    }

    return copyWith(operations: newOps);
  }

  /// Reset a single adjustment value to neutral.
  EditRecipe resetAdjustment(String name) => withAdjustment(name, 0.0);

  /// Reset all adjustments to neutral (removes the adjustment operation).
  EditRecipe resetAllAdjustments() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.adjustment);
    return copyWith(operations: newOps);
  }

  // ==========================================================================
  // CREATIVE OPERATION MODIFIERS
  // ==========================================================================

  /// Set or update the filter operation.
  EditRecipe withFilter(String presetId, double intensity) {
    final newOp = EditOperation.filter(
      presetId: presetId,
      intensity: intensity,
    );
    return _replaceOrAppend(EditOperationType.filter, newOp);
  }

  /// Remove the filter operation.
  EditRecipe withoutFilter() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.filter);
    return copyWith(operations: newOps);
  }

  /// Set or update the blur effect.
  EditRecipe withBlur(double radius, double strength) {
    final newOp = EditOperation.blur(radius: radius, strength: strength);
    return _replaceOrAppend(EditOperationType.blur, newOp);
  }

  /// Set or update the grain effect.
  EditRecipe withGrain(double intensity, double size) {
    final newOp = EditOperation.grain(intensity: intensity, size: size);
    return _replaceOrAppend(EditOperationType.grain, newOp);
  }

  /// Set or update the fade effect.
  EditRecipe withFade(double intensity) {
    final newOp = EditOperation.fade(intensity: intensity);
    return _replaceOrAppend(EditOperationType.fade, newOp);
  }

  /// Set or update the drawing layer.
  EditRecipe withDrawing(DrawingLayer layer) {
    final newOp = EditOperation.drawing(strokes: layer.toMap()['strokes']);
    return _replaceOrAppend(EditOperationType.drawing, newOp);
  }

  /// Set or update text layers.
  EditRecipe withTextLayers(List<TextLayer> layers) {
    final newOp = EditOperation.text(
      layers: layers.map((l) => l.toMap()).toList(),
    );
    return _replaceOrAppend(EditOperationType.text, newOp);
  }

  /// Set or update the frame.
  EditRecipe withFrame(FrameConfig config) {
    final newOp = EditOperation.frame(
      width: config.width,
      color: config.color,
      opacity: config.opacity,
      cornerRadius: config.cornerRadius,
      roundedCorners: config.roundedCorners,
      imageCornerRadius: config.imageCornerRadius,
    );
    return _replaceOrAppend(EditOperationType.frame, newOp);
  }

  /// Remove the frame operation.
  EditRecipe withoutFrame() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.frame);
    return copyWith(operations: newOps);
  }

  /// Remove all creative edits (filter, effects, drawing, text, frame).
  EditRecipe withoutCreativeEdits() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.isCreative);
    return copyWith(operations: newOps);
  }

  // ==========================================================================
  // AI OPERATION MODIFIERS (Phase 21)
  // ==========================================================================

  /// Set or update background removal.
  EditRecipe withBackgroundRemoval({String? maskId, double feather = 0.02}) {
    final newOp = EditOperation.backgroundRemoval(
      maskId: maskId,
      feather: feather,
    );
    return _replaceOrAppend(EditOperationType.backgroundRemoval, newOp);
  }

  /// Remove background removal.
  EditRecipe withoutBackgroundRemoval() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.backgroundRemoval);
    return copyWith(operations: newOps);
  }

  /// Set or update background replacement.
  EditRecipe withBackgroundReplacement({
    String? maskId,
    String replacementType = 'solid',
    int color = 0xFFFFFFFF,
    String? imagePath,
    double feather = 0.02,
  }) {
    final newOp = EditOperation.backgroundReplacement(
      maskId: maskId,
      replacementType: replacementType,
      color: color,
      imagePath: imagePath,
      feather: feather,
    );
    return _replaceOrAppend(EditOperationType.backgroundReplacement, newOp);
  }

  /// Remove background replacement.
  EditRecipe withoutBackgroundReplacement() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.backgroundReplacement);
    return copyWith(operations: newOps);
  }

  /// Set or update object removal.
  EditRecipe withObjectRemoval({required String maskId, String method = 'telea'}) {
    final newOp = EditOperation.objectRemoval(maskId: maskId, method: method);
    return _replaceOrAppend(EditOperationType.objectRemoval, newOp);
  }

  /// Remove object removal.
  EditRecipe withoutObjectRemoval() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.objectRemoval);
    return copyWith(operations: newOps);
  }

  /// Set or update inpainting.
  EditRecipe withInpainting({
    required String maskId,
    String method = 'telea',
    double radius = 3.0,
  }) {
    final newOp = EditOperation.inpainting(
      maskId: maskId,
      method: method,
      radius: radius,
    );
    return _replaceOrAppend(EditOperationType.inpainting, newOp);
  }

  /// Set or update enhancement.
  EditRecipe withEnhancement({double strength = 0.5, bool auto = true}) {
    final newOp = EditOperation.enhancement(strength: strength, auto: auto);
    return _replaceOrAppend(EditOperationType.enhancement, newOp);
  }

  /// Remove enhancement.
  EditRecipe withoutEnhancement() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.enhancement);
    return copyWith(operations: newOps);
  }

  /// Set or update upscaling.
  EditRecipe withUpscaling({int scale = 2, String? modelId}) {
    final newOp = EditOperation.upscaling(scale: scale, modelId: modelId);
    return _replaceOrAppend(EditOperationType.upscaling, newOp);
  }

  /// Remove upscaling.
  EditRecipe withoutUpscaling() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.upscaling);
    return copyWith(operations: newOps);
  }

  /// Set or update denoising.
  EditRecipe withDenoising({double strength = 0.5, String method = 'bilateral'}) {
    final newOp = EditOperation.denoising(strength: strength, method: method);
    return _replaceOrAppend(EditOperationType.denoising, newOp);
  }

  /// Remove denoising.
  EditRecipe withoutDenoising() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.denoising);
    return copyWith(operations: newOps);
  }

  /// Set or update smart crop.
  EditRecipe withSmartCrop({String strategy = 'centerWeighted'}) {
    final newOp = EditOperation.smartCrop(strategy: strategy);
    return _replaceOrAppend(EditOperationType.smartCrop, newOp);
  }

  /// Set or update auto enhance.
  EditRecipe withAutoEnhance({required Map<String, double> adjustments}) {
    final newOp = EditOperation.autoEnhance(adjustments: adjustments);
    return _replaceOrAppend(EditOperationType.autoEnhance, newOp);
  }

  /// Remove auto enhance.
  EditRecipe withoutAutoEnhance() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.type == EditOperationType.autoEnhance);
    return copyWith(operations: newOps);
  }

  /// Remove all AI edits.
  EditRecipe withoutAiEdits() {
    final newOps = List<EditOperation>.from(operations)
      ..removeWhere((op) => op.isCreative);
    return copyWith(operations: newOps);
  }

  /// Helper: replace an existing operation of the same type or append.
  EditRecipe _replaceOrAppend(EditOperationType type, EditOperation newOp) {
    final newOps = List<EditOperation>.from(operations);
    final idx = newOps.indexWhere((op) => op.type == type);
    if (idx >= 0) {
      newOps[idx] = newOp;
    } else {
      newOps.add(newOp);
    }
    return copyWith(operations: newOps);
  }

  /// The effective crop rectangle from all crop operations in the recipe.
  /// Multiple crops are composited (each subsequent crop operates within
  /// the previous crop's coordinate space).
  CropRect get effectiveCrop {
    var crop = CropRect.full();
    for (final op in operations) {
      if (op.type == EditOperationType.crop) {
        crop = CropRect(
          left: crop.left + op.cropLeft * crop.width,
          top: crop.top + op.cropTop * crop.height,
          width: crop.width * op.cropWidth,
          height: crop.height * op.cropHeight,
        );
      }
    }
    return crop;
  }

  /// Combined rotation angle (rotate + straighten) in degrees.
  double get effectiveRotation {
    var total = 0.0;
    for (final op in operations) {
      if (op.type == EditOperationType.rotate ||
          op.type == EditOperationType.straighten) {
        total += op.degrees;
      }
    }
    return total;
  }

  /// Whether the image is flipped (XOR of horizontal and vertical flips).
  bool get isFlippedHorizontally {
    var count = 0;
    for (final op in operations) {
      if (op.type == EditOperationType.flip && op.isHorizontalFlip) count++;
    }
    return count.isOdd;
  }

  bool get isFlippedVertically {
    var count = 0;
    for (final op in operations) {
      if (op.type == EditOperationType.flip && op.isVerticalFlip) count++;
    }
    return count.isOdd;
  }

  /// Summary of what this recipe does (for UI display).
  String get summary {
    if (isEmpty) return 'No edits';
    final parts = <String>[];
    final hasCrop = operations.any(
      (op) => op.type == EditOperationType.crop && !op.isNoOp,
    );
    final rotation = effectiveRotation;
    final hasFlip = isFlippedHorizontally || isFlippedVertically;
    final hasStraighten = operations.any(
      (op) => op.type == EditOperationType.straighten && !op.isNoOp,
    );

    if (hasCrop) parts.add('Cropped');
    if (rotation != 0) parts.add('Rotated ${rotation.toStringAsFixed(0)}°');
    if (hasFlip) {
      if (isFlippedHorizontally && isFlippedVertically) {
        parts.add('Flipped');
      } else if (isFlippedHorizontally) {
        parts.add('Flipped H');
      } else {
        parts.add('Flipped V');
      }
    }
    if (hasStraighten && rotation == 0) {
      final straighten = operations.firstWhere(
        (op) => op.type == EditOperationType.straighten,
      );
      parts.add('Straightened ${straighten.degrees.toStringAsFixed(1)}°');
    }

    // Add adjustment summary
    final adjOp = adjustmentOperation;
    if (adjOp != null && adjOp.hasNonNeutralAdjustments) {
      final adjSummary = adjOp.adjustmentSummary;
      if (adjSummary.isNotEmpty && adjSummary != 'No adjustments') {
        parts.add(adjSummary);
      }
    }

    // Add creative edit summaries
    if (hasFilter) {
      final fid = filterOperation!.filterPresetId;
      parts.add('Filter: $fid');
    }
    if (hasEffects) {
      final effects = <String>[];
      if (blurOperation != null && !blurOperation!.isNoOp) effects.add('Blur');
      if (grainOperation != null && !grainOperation!.isNoOp) {
        effects.add('Grain');
      }
      if (fadeOperation != null && !fadeOperation!.isNoOp) {
        effects.add('Fade');
      }
      parts.add(effects.join('+'));
    }
    if (hasDrawing) {
      parts.add('Drawing');
    }
    if (hasText) {
      parts.add('Text');
    }
    if (hasFrame) {
      parts.add('Frame');
    }

    // Add resize / perspective summaries (Phase 14)
    final resizeOps = operations.where((op) => op.type == EditOperationType.resize && !op.isNoOp).toList();
    if (resizeOps.isNotEmpty) {
      final r = resizeOps.first;
      parts.add('Resized ${r.resizeWidth}×${r.resizeHeight}');
    }
    final perspOps = operations.where((op) => op.type == EditOperationType.perspective && !op.isNoOp).toList();
    if (perspOps.isNotEmpty) parts.add('Perspective');

    // Add AI operation summaries
    for (final summary in aiOperationSummaries) {
      if (!parts.contains(summary)) parts.add(summary);
    }

    return parts.isEmpty ? 'No edits' : parts.join(', ');
  }

  // Phase 14 helpers: resize & perspective
  EditRecipe withResize({required int width, required int height, bool maintainAspect = true}) {
    return _replaceOrAppend(EditOperationType.resize, EditOperation.resize(width: width, height: height, maintainAspect: maintainAspect));
  }
  EditRecipe withoutResize() {
    final newOps = List<EditOperation>.from(operations)..removeWhere((op) => op.type == EditOperationType.resize);
    return copyWith(operations: newOps);
  }
  EditRecipe withPerspective({double tlX = 0, double tlY = 0, double trX = 0, double trY = 0, double brX = 0, double brY = 0, double blX = 0, double blY = 0}) {
    return _replaceOrAppend(EditOperationType.perspective, EditOperation.perspective(tlX: tlX, tlY: tlY, trX: trX, trY: trY, brX: brX, brY: brY, blX: blX, blY: blY));
  }
  EditRecipe withoutPerspective() {
    final newOps = List<EditOperation>.from(operations)..removeWhere((op) => op.type == EditOperationType.perspective);
    return copyWith(operations: newOps);
  }
  bool get hasResize => operations.any((op) => op.type == EditOperationType.resize && !op.isNoOp);
  bool get hasPerspective => operations.any((op) => op.type == EditOperationType.perspective && !op.isNoOp);

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> toMap() {
    return {
      'photo_id': photoId,
      'operations': operations.map((op) => op.toMap()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'version': version,
      'is_exported': isExported ? 1 : 0,
      'exported_path': exportedPath,
    };
  }

  /// Serialize operations to a JSON string (for database storage).
  String operationsToJson() {
    return jsonEncode(operations.map((op) => op.toMap()).toList());
  }

  /// Deserialize operations from a JSON string.
  static List<EditOperation> operationsFromJson(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => EditOperation.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  factory EditRecipe.fromMap(
    Map<String, dynamic> row, {
    String? operationsJson,
  }) {
    return EditRecipe(
      photoId: row['photo_id'] as String,
      operations: operationsJson != null
          ? EditRecipe.operationsFromJson(operationsJson)
          : (row['operations'] as List?)
                  ?.map(
                    (e) => EditOperation.fromMap(e as Map<String, dynamic>),
                  )
                  .toList() ??
              [],
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      version: row['version'] as int? ?? 1,
      isExported: (row['is_exported'] as int? ?? 0) == 1,
      exportedPath: row['exported_path'] as String?,
    );
  }

  EditRecipe copyWith({
    String? photoId,
    List<EditOperation>? operations,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    bool? isExported,
    String? exportedPath,
  }) {
    return EditRecipe(
      photoId: photoId ?? this.photoId,
      operations: operations ?? this.operations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      isExported: isExported ?? this.isExported,
      exportedPath: exportedPath ?? this.exportedPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditRecipe &&
          runtimeType == other.runtimeType &&
          photoId == other.photoId &&
          _listEquals(operations, other.operations);

  @override
  int get hashCode => Object.hash(photoId, Object.hashAll(operations));

  static bool _listEquals(List<EditOperation> a, List<EditOperation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
