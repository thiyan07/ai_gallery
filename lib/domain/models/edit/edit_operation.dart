import 'dart:math' as math;
import 'dart:ui' as ui;

/// Type of non-destructive edit operation.
enum EditOperationType {
  crop,
  rotate,
  flip,
  straighten,
  adjustment,
  filter,
  blur,
  grain,
  fade,
  drawing,
  text,
  frame,

  // AI editing operations (Phase 21)
  backgroundRemoval,
  backgroundReplacement,
  objectRemoval,
  inpainting,
  enhancement,
  upscaling,
  denoising,
  smartCrop,
  aiAnalysis,
  autoEnhance,

  // Advanced color operations (Phase 29)
  curves,
  hsl,
  selectiveColor,
  editGroup,

  // Phase 14 advanced editing: resize + perspective
  resize,
  perspective,
}

/// Default values for all adjustment parameters.
/// Neutral = 0.0 for all adjustments. Range is -1.0 to +1.0 internally.
class AdjustmentDefaults {
  AdjustmentDefaults._();

  static const double exposure = 0.0;
  static const double brightness = 0.0;
  static const double contrast = 0.0;
  static const double highlights = 0.0;
  static const double shadows = 0.0;
  static const double whites = 0.0;
  static const double blacks = 0.0;
  static const double saturation = 0.0;
  static const double vibrance = 0.0;
  static const double temperature = 0.0;
  static const double tint = 0.0;
  static const double sharpness = 0.0;
  static const double clarity = 0.0;
  static const double vignette = 0.0;

  static const Map<String, double> all = {
    'exposure': exposure,
    'brightness': brightness,
    'contrast': contrast,
    'highlights': highlights,
    'shadows': shadows,
    'whites': whites,
    'blacks': blacks,
    'saturation': saturation,
    'vibrance': vibrance,
    'temperature': temperature,
    'tint': tint,
    'sharpness': sharpness,
    'clarity': clarity,
    'vignette': vignette,
  };

  /// All adjustment parameter names in rendering pipeline order.
  static const List<String> pipelineOrder = [
    'exposure',
    'brightness',
    'contrast',
    'highlights',
    'shadows',
    'whites',
    'blacks',
    'temperature',
    'tint',
    'saturation',
    'vibrance',
    'clarity',
    'sharpness',
    'vignette',
  ];

  /// UI display groups for the editor.
  static const List<String> lightGroup = [
    'exposure', 'brightness', 'contrast',
    'highlights', 'shadows', 'whites', 'blacks',
  ];

  static const List<String> colorGroup = [
    'saturation', 'vibrance', 'temperature', 'tint',
  ];

  static const List<String> detailGroup = [
    'sharpness', 'clarity', 'vignette',
  ];

  /// HSL color channel names.
  static const List<String> hslChannels = [
    'red', 'orange', 'yellow', 'green', 'aqua', 'blue', 'purple', 'magenta',
  ];

  /// HSL adjustment sub-parameters.
  static const List<String> hslParams = ['hue', 'saturation', 'luminance'];

  /// Human-readable labels for each adjustment.
  static const Map<String, String> labels = {
    'exposure': 'Exposure',
    'brightness': 'Brightness',
    'contrast': 'Contrast',
    'highlights': 'Highlights',
    'shadows': 'Shadows',
    'whites': 'Whites',
    'blacks': 'Blacks',
    'saturation': 'Saturation',
    'vibrance': 'Vibrance',
    'temperature': 'Temperature',
    'tint': 'Tint',
    'sharpness': 'Sharpness',
    'clarity': 'Clarity',
    'vignette': 'Vignette',
  };

  /// Icons for each adjustment.
  static const Map<String, String> iconNames = {
    'exposure': 'exposure',
    'brightness': 'brightness',
    'contrast': 'contrast',
    'highlights': 'highlight',
    'shadows': 'shadow',
    'whites': 'white_balance',
    'blacks': 'tonality',
    'saturation': 'palette',
    'vibrance': 'vibrance',
    'temperature': 'thermostat',
    'tint': 'tint',
    'sharpness': 'sharpness',
    'clarity': 'auto_fix_high',
    'vignette': 'vignette',
  };

  /// Clamp an adjustment value to [-1.0, +1.0].
  static double clampValue(double value) => value.clamp(-1.0, 1.0);
}

/// A single non-destructive edit operation applied to a photo.
///
/// Operations are serializable and versionable. Each operation stores
/// its parameters in a resolution-independent way (relative coordinates
/// for crop, degrees for rotation/straightening, axis for flip,
/// normalized values for adjustments).
class EditOperation {
  final EditOperationType type;
  final Map<String, dynamic> params;

  const EditOperation({
    required this.type,
    required this.params,
  });

  /// Crop operation: relative coordinates (0.0–1.0) of the crop rectangle.
  /// Params: left, top, width, height (all double, 0.0–1.0).
  factory EditOperation.crop({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    assert(left >= 0.0 && left <= 1.0);
    assert(top >= 0.0 && top <= 1.0);
    assert(width > 0.0 && width <= 1.0);
    assert(height > 0.0 && height <= 1.0);
    assert(left + width <= 1.0);
    assert(top + height <= 1.0);
    return EditOperation(
      type: EditOperationType.crop,
      params: {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      },
    );
  }

  /// Rotation operation: angle in degrees (positive = clockwise).
  /// Common values: 0, 90, 180, 270. Arbitrary angles supported.
  factory EditOperation.rotate({required double degrees}) {
    return EditOperation(
      type: EditOperationType.rotate,
      params: {'degrees': degrees},
    );
  }

  /// Flip operation: mirror the image along an axis.
  /// [horizontal] flips left-right, [vertical] flips top-bottom.
  factory EditOperation.flip({
    required bool horizontal,
    required bool vertical,
  }) {
    return EditOperation(
      type: EditOperationType.flip,
      params: {'horizontal': horizontal, 'vertical': vertical},
    );
  }

  /// Straighten operation: rotation correction in degrees.
  /// Positive = clockwise tilt correction. Range: -45.0 to 45.0.
  factory EditOperation.straighten({required double degrees}) {
    final clamped = degrees.clamp(-45.0, 45.0);
    return EditOperation(
      type: EditOperationType.straighten,
      params: {'degrees': clamped},
    );
  }

  /// Adjustment operation: holds ALL current adjustment values.
  ///
  /// This is a SINGLE operation in the recipe that stores all 14 adjustment
  /// parameters. When a slider changes, this operation's params are updated
  /// (replaced) rather than creating a new operation.
  ///
  /// All values are normalized to [-1.0, +1.0] internally.
  /// UI maps to/from the appropriate user-facing range.
  factory EditOperation.adjustment({
    double exposure = 0.0,
    double brightness = 0.0,
    double contrast = 0.0,
    double highlights = 0.0,
    double shadows = 0.0,
    double whites = 0.0,
    double blacks = 0.0,
    double saturation = 0.0,
    double vibrance = 0.0,
    double temperature = 0.0,
    double tint = 0.0,
    double sharpness = 0.0,
    double clarity = 0.0,
    double vignette = 0.0,
  }) {
    return EditOperation(
      type: EditOperationType.adjustment,
      params: {
        'exposure': AdjustmentDefaults.clampValue(exposure),
        'brightness': AdjustmentDefaults.clampValue(brightness),
        'contrast': AdjustmentDefaults.clampValue(contrast),
        'highlights': AdjustmentDefaults.clampValue(highlights),
        'shadows': AdjustmentDefaults.clampValue(shadows),
        'whites': AdjustmentDefaults.clampValue(whites),
        'blacks': AdjustmentDefaults.clampValue(blacks),
        'saturation': AdjustmentDefaults.clampValue(saturation),
        'vibrance': AdjustmentDefaults.clampValue(vibrance),
        'temperature': AdjustmentDefaults.clampValue(temperature),
        'tint': AdjustmentDefaults.clampValue(tint),
        'sharpness': AdjustmentDefaults.clampValue(sharpness),
        'clarity': AdjustmentDefaults.clampValue(clarity),
        'vignette': AdjustmentDefaults.clampValue(vignette),
      },
    );
  }

  /// Create an adjustment operation with a single value changed.
  /// All other values come from the existing adjustment or default to 0.
  EditOperation adjustmentWith(String key, double value) {
    assert(type == EditOperationType.adjustment);
    final newParams = Map<String, dynamic>.from(params);
    newParams[key] = AdjustmentDefaults.clampValue(value);
    return EditOperation(type: type, params: newParams);
  }

  // ==========================================================================
  // CREATIVE OPERATIONS (Phase 20)
  // ==========================================================================

  /// Filter preset operation.
  /// Params: presetId (String), intensity (double 0.0–1.0).
  factory EditOperation.filter({
    required String presetId,
    double intensity = 1.0,
  }) {
    return EditOperation(
      type: EditOperationType.filter,
      params: {
        'presetId': presetId,
        'intensity': intensity.clamp(0.0, 1.0),
      },
    );
  }

  /// Create a filter operation with a different intensity.
  EditOperation filterWithIntensity(double intensity) {
    assert(type == EditOperationType.filter);
    return EditOperation(
      type: type,
      params: {
        ...params,
        'intensity': intensity.clamp(0.0, 1.0),
      },
    );
  }

  /// Blur effect operation.
  /// Params: radius (double, 0–20), strength (double 0.0–1.0).
  factory EditOperation.blur({
    double radius = 5.0,
    double strength = 0.5,
  }) {
    return EditOperation(
      type: EditOperationType.blur,
      params: {
        'radius': radius.clamp(0.0, 20.0),
        'strength': strength.clamp(0.0, 1.0),
      },
    );
  }

  /// Film grain effect operation.
  /// Params: intensity (double 0.0–1.0), size (double 0.0–1.0).
  factory EditOperation.grain({
    double intensity = 0.0,
    double size = 0.5,
  }) {
    return EditOperation(
      type: EditOperationType.grain,
      params: {
        'intensity': intensity.clamp(0.0, 1.0),
        'size': size.clamp(0.0, 1.0),
      },
    );
  }

  /// Fade effect operation.
  /// Params: intensity (double 0.0–1.0).
  factory EditOperation.fade({double intensity = 0.0}) {
    return EditOperation(
      type: EditOperationType.fade,
      params: {
        'intensity': intensity.clamp(0.0, 1.0),
      },
    );
  }

  /// Drawing layer operation.
  /// Params: strokesJson (List<Map>).
  factory EditOperation.drawing({required List<Map<String, dynamic>> strokes}) {
    return EditOperation(
      type: EditOperationType.drawing,
      params: {
        'strokes': strokes,
      },
    );
  }

  /// Text layer operation.
  /// Params: layersJson (List<Map>).
  factory EditOperation.text({required List<Map<String, dynamic>> layers}) {
    return EditOperation(
      type: EditOperationType.text,
      params: {
        'layers': layers,
      },
    );
  }

  /// Frame/border operation.
  /// Params: width (double), color (int ARGB), opacity (double),
  /// cornerRadius (double), roundedCorners (bool), imageCornerRadius (double).
  factory EditOperation.frame({
    double width = 0.0,
    int color = 0xFFFFFFFF,
    double opacity = 1.0,
    double cornerRadius = 0.0,
    bool roundedCorners = false,
    double imageCornerRadius = 0.0,
  }) {
    return EditOperation(
      type: EditOperationType.frame,
      params: {
        'width': width.clamp(0.0, 0.2),
        'color': color,
        'opacity': opacity.clamp(0.0, 1.0),
        'cornerRadius': cornerRadius.clamp(0.0, 1.0),
        'roundedCorners': roundedCorners,
        'imageCornerRadius': imageCornerRadius.clamp(0.0, 0.1),
      },
    );
  }

  // ==========================================================================
  // AI OPERATIONS (Phase 21)
  // ==========================================================================

  /// Background removal operation.
  /// Removes the background, leaving the subject as transparent.
  /// Params: maskId (String, reference to saved mask), feather (double 0.0–0.1).
  factory EditOperation.backgroundRemoval({
    String? maskId,
    double feather = 0.02,
  }) {
    return EditOperation(
      type: EditOperationType.backgroundRemoval,
      params: {
        'maskId': maskId,
        'feather': feather.clamp(0.0, 0.1),
      },
    );
  }

  /// Background replacement operation.
  /// Replaces the background with a solid color or another image.
  /// Params: replacementType ('solid' | 'image'), color (int ARGB),
  /// imagePath (String?), maskId (String).
  factory EditOperation.backgroundReplacement({
    String? maskId,
    String replacementType = 'solid',
    int color = 0xFFFFFFFF,
    String? imagePath,
    double feather = 0.02,
  }) {
    return EditOperation(
      type: EditOperationType.backgroundReplacement,
      params: {
        'maskId': maskId,
        'replacementType': replacementType,
        'color': color,
        'imagePath': imagePath,
        'feather': feather.clamp(0.0, 0.1),
      },
    );
  }

  /// Object removal operation.
  /// Removes the selected object and fills the area (inpainting).
  /// Params: maskId (String), method ('telea' | 'ns' | 'patchMatch').
  factory EditOperation.objectRemoval({
    required String maskId,
    String method = 'telea',
  }) {
    return EditOperation(
      type: EditOperationType.objectRemoval,
      params: {
        'maskId': maskId,
        'method': method,
      },
    );
  }

  /// Inpainting operation (general fill).
  /// Fills masked region using surrounding context.
  /// Params: maskId (String), method ('telea' | 'ns' | 'patchMatch'),
  /// radius (double, inpainting radius in pixels).
  factory EditOperation.inpainting({
    required String maskId,
    String method = 'telea',
    double radius = 3.0,
  }) {
    return EditOperation(
      type: EditOperationType.inpainting,
      params: {
        'maskId': maskId,
        'method': method,
        'radius': radius.clamp(1.0, 20.0),
      },
    );
  }

  /// AI enhancement operation.
  /// Improves image quality using histogram analysis + adjustments.
  /// Params: strength (double 0.0–1.0), auto (bool).
  factory EditOperation.enhancement({
    double strength = 0.5,
    bool auto = true,
  }) {
    return EditOperation(
      type: EditOperationType.enhancement,
      params: {
        'strength': strength.clamp(0.0, 1.0),
        'auto': auto,
      },
    );
  }

  /// AI upscaling operation.
  /// Upscales the image using Real-ESRGAN or bicubic fallback.
  /// Params: scale (int, 2 or 4), modelId (String?).
  factory EditOperation.upscaling({
    int scale = 2,
    String? modelId,
  }) {
    return EditOperation(
      type: EditOperationType.upscaling,
      params: {
        'scale': scale.clamp(2, 4),
        'modelId': modelId,
      },
    );
  }

  /// AI denoising operation.
  /// Reduces noise using bilateral filter or NL-means.
  /// Params: strength (double 0.0–1.0), method ('bilateral' | 'nlmeans').
  factory EditOperation.denoising({
    double strength = 0.5,
    String method = 'bilateral',
  }) {
    return EditOperation(
      type: EditOperationType.denoising,
      params: {
        'strength': strength.clamp(0.0, 1.0),
        'method': method,
      },
    );
  }

  /// Smart crop operation.
  /// Crops the image using composition rules (rule of thirds, face-aware).
  /// Params: strategy ('ruleOfThirds' | 'faceAware' | 'centerWeighted').
  factory EditOperation.smartCrop({
    String strategy = 'centerWeighted',
  }) {
    return EditOperation(
      type: EditOperationType.smartCrop,
      params: {
        'strategy': strategy,
      },
    );
  }

  /// AI analysis operation (metadata).
  /// Stores analysis results (lighting, color, composition scores).
  /// This is a metadata operation — it does not transform pixels.
  /// Params: analysisResults (Map<String, dynamic>).
  factory EditOperation.aiAnalysis({
    required Map<String, dynamic> analysisResults,
  }) {
    return EditOperation(
      type: EditOperationType.aiAnalysis,
      params: {
        'analysisResults': analysisResults,
      },
    );
  }

  /// Auto enhance operation.
  /// Automatically applies optimal adjustments based on image analysis.
  /// Params: adjustments (Map<String, double> — the computed adjustments).
  factory EditOperation.autoEnhance({
    required Map<String, double> adjustments,
  }) {
    return EditOperation(
      type: EditOperationType.autoEnhance,
      params: {
        'adjustments': adjustments,
      },
    );
  }

  // ==========================================================================
  // ADVANCED COLOR OPERATIONS (Phase 29)
  // ==========================================================================

  /// Curves (tone curve) operation.
  /// Params: rgbPoints (List<Map> with 'x','y' 0.0–1.0), channelPoints
  /// (Map<String, List<Map>> for R/G/B/L), intensity (double 0.0–1.0).
  factory EditOperation.curves({
    List<Map<String, double>>? rgbPoints,
    Map<String, List<Map<String, double>>>? channelPoints,
    double intensity = 1.0,
  }) {
    return EditOperation(
      type: EditOperationType.curves,
      params: {
        'rgbPoints': rgbPoints ?? _defaultCurvePoints(),
        'channelPoints': channelPoints ?? {},
        'intensity': intensity.clamp(0.0, 1.0),
      },
    );
  }

  static List<Map<String, double>> _defaultCurvePoints() => const [
        {'x': 0.0, 'y': 0.0},
        {'x': 1.0, 'y': 1.0},
      ];

  /// HSL (Hue/Saturation/Luminance) per-channel adjustment.
  /// Params: channels (Map<String, Map<String, double>> keyed by channel name
  /// 'red','orange','yellow','green','aqua','blue','purple','magenta',
  /// each with sub-keys 'hue','saturation','luminance' in [-1.0, +1.0]).
  factory EditOperation.hsl({
    Map<String, Map<String, double>>? channels,
  }) {
    return EditOperation(
      type: EditOperationType.hsl,
      params: {
        'channels': channels ?? {},
      },
    );
  }

  /// Selective color adjustment via mask.
  /// Applies per-channel color adjustments only within a masked region.
  /// Params: maskId (String), channels (Map similar to hsl), feather (double).
  factory EditOperation.selectiveColor({
    required String maskId,
    Map<String, Map<String, double>>? channels,
    double feather = 0.02,
  }) {
    return EditOperation(
      type: EditOperationType.selectiveColor,
      params: {
        'maskId': maskId,
        'channels': channels ?? {},
        'feather': feather.clamp(0.0, 0.1),
      },
    );
  }

  /// Edit group: a named collection of operations that can be applied,
  /// copied, pasted, or batch-applied as a unit.
  /// Params: name (String), operations (List<Map> serialized operations),
  /// groupName (String — 'user_preset'|'copy_paste'|'batch'|'ai_plan').
  factory EditOperation.editGroup({
    required String name,
    required List<EditOperation> operations,
    String groupName = 'user_preset',
  }) {
    return EditOperation(
      type: EditOperationType.editGroup,
      params: {
        'name': name,
        'operations': operations.map((op) => op.toMap()).toList(),
        'groupName': groupName,
      },
    );
  }

  // ==========================================================================
  // PHASE 14: RESIZE + PERSPECTIVE
  // ==========================================================================

  /// Resize operation: scales the image to explicit dimensions.
  /// Params: width (int), height (int), maintainAspect (bool), method (String).
  factory EditOperation.resize({
    required int width,
    required int height,
    bool maintainAspect = true,
    String method = 'lanczos',
  }) {
    return EditOperation(
      type: EditOperationType.resize,
      params: {
        'width': width.clamp(1, 8000),
        'height': height.clamp(1, 8000),
        'maintainAspect': maintainAspect,
        'method': method,
      },
    );
  }

  /// Perspective correction operation: keystone/perspective warp.
  /// Params: tl/br style corner deltas normalized to image size [-0.5..0.5].
  /// When all deltas are 0, it is a no-op (identity).
  factory EditOperation.perspective({
    double tlX = 0.0,
    double tlY = 0.0,
    double trX = 0.0,
    double trY = 0.0,
    double brX = 0.0,
    double brY = 0.0,
    double blX = 0.0,
    double blY = 0.0,
  }) {
    return EditOperation(
      type: EditOperationType.perspective,
      params: {
        'tlX': tlX.clamp(-0.5, 0.5),
        'tlY': tlY.clamp(-0.5, 0.5),
        'trX': trX.clamp(-0.5, 0.5),
        'trY': trY.clamp(-0.5, 0.5),
        'brX': brX.clamp(-0.5, 0.5),
        'brY': brY.clamp(-0.5, 0.5),
        'blX': blX.clamp(-0.5, 0.5),
        'blY': blY.clamp(-0.5, 0.5),
      },
    );
  }

  // --- Adjustment getters ---

  double get exposure => (params['exposure'] as num?)?.toDouble() ?? 0.0;
  double get brightness => (params['brightness'] as num?)?.toDouble() ?? 0.0;
  double get contrast => (params['contrast'] as num?)?.toDouble() ?? 0.0;
  double get highlights => (params['highlights'] as num?)?.toDouble() ?? 0.0;
  double get shadows => (params['shadows'] as num?)?.toDouble() ?? 0.0;
  double get whites => (params['whites'] as num?)?.toDouble() ?? 0.0;
  double get blacks => (params['blacks'] as num?)?.toDouble() ?? 0.0;
  double get saturation => (params['saturation'] as num?)?.toDouble() ?? 0.0;
  double get vibrance => (params['vibrance'] as num?)?.toDouble() ?? 0.0;
  double get temperature => (params['temperature'] as num?)?.toDouble() ?? 0.0;
  double get tint => (params['tint'] as num?)?.toDouble() ?? 0.0;
  double get sharpness => (params['sharpness'] as num?)?.toDouble() ?? 0.0;
  double get clarity => (params['clarity'] as num?)?.toDouble() ?? 0.0;
  double get vignette => (params['vignette'] as num?)?.toDouble() ?? 0.0;

  /// Get any adjustment value by name.
  double adjustmentValue(String name) {
    return (params[name] as num?)?.toDouble() ?? 0.0;
  }

  /// Get all adjustment values as a map.
  Map<String, double> get adjustmentValues {
    final result = <String, double>{};
    for (final key in AdjustmentDefaults.all.keys) {
      result[key] = adjustmentValue(key);
    }
    return result;
  }

  /// Whether this is an adjustment operation.
  bool get isAdjustment => type == EditOperationType.adjustment;

  /// Whether any adjustment value is non-neutral (non-zero).
  bool get hasNonNeutralAdjustments {
    if (type != EditOperationType.adjustment) return false;
    return AdjustmentDefaults.all.keys.any(
      (key) => adjustmentValue(key) != 0.0,
    );
  }

  /// Summary of active adjustments (for display).
  String get adjustmentSummary {
    if (type != EditOperationType.adjustment) return '';
    final parts = <String>[];
    for (final key in AdjustmentDefaults.all.keys) {
      final val = adjustmentValue(key);
      if (val != 0.0) {
        final label = AdjustmentDefaults.labels[key] ?? key;
        final sign = val > 0 ? '+' : '';
        parts.add('$label $sign${(val * 100).round()}');
      }
    }
    return parts.isEmpty ? 'No adjustments' : parts.join(', ');
  }

  // --- Existing getters ---

  /// Whether this operation is a no-op in its current state.
  bool get isNoOp {
    return switch (type) {
      EditOperationType.crop => () {
        final l = params['left'] as double;
        final t = params['top'] as double;
        final w = params['width'] as double;
        final h = params['height'] as double;
        return l == 0.0 && t == 0.0 && w == 1.0 && h == 1.0;
      }(),
      EditOperationType.rotate => (params['degrees'] as double) % 360 == 0,
      EditOperationType.flip => !(params['horizontal'] as bool) &&
          !(params['vertical'] as bool),
      EditOperationType.straighten => (params['degrees'] as double) == 0,
      EditOperationType.adjustment => !hasNonNeutralAdjustments,
      EditOperationType.filter =>
        (params['intensity'] as double?) == 0.0,
      EditOperationType.blur =>
        (params['strength'] as double?) == 0.0,
      EditOperationType.grain =>
        (params['intensity'] as double?) == 0.0,
      EditOperationType.fade =>
        (params['intensity'] as double?) == 0.0,
      EditOperationType.drawing =>
        (params['strokes'] as List?)?.isEmpty ?? true,
      EditOperationType.text =>
        (params['layers'] as List?)?.isEmpty ?? true,
      EditOperationType.frame =>
        (params['width'] as double?) == 0.0,
      EditOperationType.backgroundRemoval =>
        (params['maskId'] as String?) == null,
      EditOperationType.backgroundReplacement =>
        (params['maskId'] as String?) == null,
      EditOperationType.objectRemoval =>
        (params['maskId'] as String?) == null,
      EditOperationType.inpainting =>
        (params['maskId'] as String?) == null,
      EditOperationType.enhancement =>
        (params['strength'] as double?) == 0.0,
      EditOperationType.upscaling =>
        (params['scale'] as int?) == 1,
      EditOperationType.denoising =>
        (params['strength'] as double?) == 0.0,
      EditOperationType.smartCrop => false,
      EditOperationType.aiAnalysis => false,
      EditOperationType.autoEnhance =>
        (params['adjustments'] as Map?)?.isEmpty ?? true,
      EditOperationType.curves => () {
        final rgb = params['rgbPoints'] as List?;
        final channels = params['channelPoints'] as Map?;
        final intensity = (params['intensity'] as num?)?.toDouble() ?? 1.0;
        final isDefaultRgb = rgb == null ||
            rgb.length == 2 &&
                (rgb[0] as Map)['x'] == 0.0 &&
                (rgb[0] as Map)['y'] == 0.0 &&
                (rgb[1] as Map)['x'] == 1.0 &&
                (rgb[1] as Map)['y'] == 1.0;
        return isDefaultRgb &&
            (channels == null || channels.isEmpty) &&
            intensity == 1.0;
      }(),
      EditOperationType.hsl => () {
        final channels = params['channels'] as Map?;
        return channels == null || channels.isEmpty;
      }(),
      EditOperationType.selectiveColor =>
        (params['maskId'] as String?) == null,
      EditOperationType.editGroup => () {
        final ops = params['operations'] as List?;
        return ops == null || ops.isEmpty;
      }(),
      EditOperationType.resize => () {
        final w = (params['width'] as num?)?.toInt() ?? 0;
        final h = (params['height'] as num?)?.toInt() ?? 0;
        return w <= 0 || h <= 0;
      }(),
      EditOperationType.perspective => () {
        final keys = ['tlX','tlY','trX','trY','brX','brY','blX','blY'];
        return keys.every((k) => (params[k] as num?)?.toDouble() == 0.0);
      }(),
    };
  }

  // --- Creative operation getters ---

  /// Filter preset ID.
  String? get filterPresetId => params['presetId'] as String?;

  /// Filter intensity (0.0–1.0).
  double get filterIntensity =>
      (params['intensity'] as num?)?.toDouble() ?? 1.0;

  /// Blur radius.
  double get blurRadius => (params['radius'] as num?)?.toDouble() ?? 5.0;

  /// Blur strength (0.0–1.0).
  double get blurStrength =>
      (params['strength'] as num?)?.toDouble() ?? 0.5;

  /// Grain intensity (0.0–1.0).
  double get grainIntensity =>
      (params['intensity'] as num?)?.toDouble() ?? 0.0;

  /// Grain size (0.0–1.0).
  double get grainSize => (params['size'] as num?)?.toDouble() ?? 0.5;

  /// Fade intensity (0.0–1.0).
  double get fadeIntensity =>
      (params['intensity'] as num?)?.toDouble() ?? 0.0;

  /// Drawing strokes as a list of maps.
  List<Map<String, dynamic>> get drawingStrokes {
    final raw = params['strokes'] as List?;
    if (raw == null) return [];
    return raw.cast<Map<String, dynamic>>();
  }

  /// Text layers as a list of maps.
  List<Map<String, dynamic>> get textLayers {
    final raw = params['layers'] as List?;
    if (raw == null) return [];
    return raw.cast<Map<String, dynamic>>();
  }

  /// Frame width.
  double get frameWidth => (params['width'] as num?)?.toDouble() ?? 0.0;

  /// Frame color (ARGB).
  int get frameColor => (params['color'] as int?) ?? 0xFFFFFFFF;

  /// Frame opacity.
  double get frameOpacity =>
      (params['opacity'] as num?)?.toDouble() ?? 1.0;

  /// Whether this is a filter operation.
  bool get isFilter => type == EditOperationType.filter;

  /// Whether this is a blur operation.
  bool get isBlur => type == EditOperationType.blur;

  /// Whether this is a grain operation.
  bool get isGrain => type == EditOperationType.grain;

  /// Whether this is a fade operation.
  bool get isFade => type == EditOperationType.fade;

  /// Whether this is a drawing operation.
  bool get isDrawing => type == EditOperationType.drawing;

  /// Whether this is a text operation.
  bool get isText => type == EditOperationType.text;

  /// Whether this is a frame operation.
  bool get isFrame => type == EditOperationType.frame;

  // --- AI operation getters ---

  /// Mask reference ID for operations that use a mask.
  String? get maskId => params['maskId'] as String?;

  /// Feather amount for mask-based operations.
  double get maskFeather =>
      (params['feather'] as num?)?.toDouble() ?? 0.02;

  /// Background replacement type ('solid' or 'image').
  String get backgroundReplacementType =>
      (params['replacementType'] as String?) ?? 'solid';

  /// Background replacement color (ARGB).
  int get backgroundColor => (params['color'] as int?) ?? 0xFFFFFFFF;

  /// Background replacement image path.
  String? get backgroundImagePath => params['imagePath'] as String?;

  /// Inpainting/object removal method.
  String get inpaintMethod =>
      (params['method'] as String?) ?? 'telea';

  /// Inpainting radius in pixels.
  double get inpaintRadius =>
      (params['radius'] as num?)?.toDouble() ?? 3.0;

  /// Enhancement strength (0.0–1.0).
  double get enhancementStrength =>
      (params['strength'] as num?)?.toDouble() ?? 0.5;

  /// Whether enhancement is auto-computed.
  bool get isAutoEnhance => (params['auto'] as bool?) ?? true;

  /// Upscaling scale factor (2 or 4).
  int get upscaleScale => (params['scale'] as int?) ?? 2;

  /// Upscaling model ID.
  String? get upscaleModelId => params['modelId'] as String?;

  /// Denoising strength (0.0–1.0).
  double get denoiseStrength =>
      (params['strength'] as num?)?.toDouble() ?? 0.5;

  /// Denoising method.
  String get denoiseMethod =>
      (params['method'] as String?) ?? 'bilateral';

  /// Smart crop strategy.
  String get smartCropStrategy =>
      (params['strategy'] as String?) ?? 'centerWeighted';

  /// AI analysis results map.
  Map<String, dynamic> get analysisResults {
    final raw = params['analysisResults'] as Map?;
    if (raw == null) return {};
    return raw.cast<String, dynamic>();
  }

  /// Auto-enhance adjustments map.
  Map<String, double> get autoEnhanceAdjustments {
    final raw = params['adjustments'] as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  /// Whether this is a background removal operation.
  bool get isBackgroundRemoval => type == EditOperationType.backgroundRemoval;

  /// Whether this is a background replacement operation.
  bool get isBackgroundReplacement =>
      type == EditOperationType.backgroundReplacement;

  /// Whether this is an object removal operation.
  bool get isObjectRemoval => type == EditOperationType.objectRemoval;

  /// Whether this is an inpainting operation.
  bool get isInpainting => type == EditOperationType.inpainting;

  /// Whether this is an enhancement operation.
  bool get isEnhancement => type == EditOperationType.enhancement;

  /// Whether this is an upscaling operation.
  bool get isUpscaling => type == EditOperationType.upscaling;

  /// Whether this is a denoising operation.
  bool get isDenoising => type == EditOperationType.denoising;

  /// Whether this is a smart crop operation.
  bool get isSmartCrop => type == EditOperationType.smartCrop;

  /// Whether this is an AI analysis operation.
  bool get isAiAnalysis => type == EditOperationType.aiAnalysis;

  /// Whether this is an auto-enhance operation.
  bool get isAutoEnhanceOp => type == EditOperationType.autoEnhance;

  // --- Phase 29 operation getters ---

  /// Curves RGB control points.
  List<Map<String, double>> get curvesRgbPoints {
    final raw = params['rgbPoints'] as List?;
    if (raw == null) return EditOperation._defaultCurvePoints();
    return raw.cast<Map<String, double>>();
  }

  /// Curves per-channel control points (R, G, B, Luminance).
  Map<String, List<Map<String, double>>> get curvesChannelPoints {
    final raw = params['channelPoints'] as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(
          k as String,
          (v as List).cast<Map<String, double>>(),
        ));
  }

  /// Curves intensity (0.0–1.0).
  double get curvesIntensity =>
      (params['intensity'] as num?)?.toDouble() ?? 1.0;

  /// HSL channels map.
  Map<String, Map<String, double>> get hslChannels {
    final raw = params['channels'] as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(
          k as String,
          (v as Map).map((k2, v2) => MapEntry(
                k2 as String,
                (v2 as num).toDouble(),
              )),
        ));
  }

  /// Selective color channels (same structure as HSL).
  Map<String, Map<String, double>> get selectiveColorChannels {
    final raw = params['channels'] as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(
          k as String,
          (v as Map).map((k2, v2) => MapEntry(
                k2 as String,
                (v2 as num).toDouble(),
              )),
        ));
  }

  /// Edit group name.
  String get groupName => (params['name'] as String?) ?? '';

  /// Edit group type tag.
  String get groupTag => (params['groupName'] as String?) ?? 'user_preset';

  /// Edit group operations deserialized.
  List<EditOperation> get groupOperations {
    final raw = params['operations'] as List?;
    if (raw == null) return [];
    return raw
        .map((e) => EditOperation.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Whether this is a curves operation.
  bool get isCurves => type == EditOperationType.curves;

  /// Whether this is an HSL operation.
  bool get isHsl => type == EditOperationType.hsl;

  /// Whether this is a selective color operation.
  bool get isSelectiveColor => type == EditOperationType.selectiveColor;

  /// Whether this is an edit group operation.
  bool get isEditGroup => type == EditOperationType.editGroup;

  /// Whether this is a creative (non-geometric, non-adjustment) operation.
  bool get isCreative =>
      type == EditOperationType.filter ||
      type == EditOperationType.blur ||
      type == EditOperationType.grain ||
      type == EditOperationType.fade ||
      type == EditOperationType.drawing ||
      type == EditOperationType.text ||
      type == EditOperationType.frame ||
      type == EditOperationType.backgroundRemoval ||
      type == EditOperationType.backgroundReplacement ||
      type == EditOperationType.objectRemoval ||
      type == EditOperationType.inpainting ||
      type == EditOperationType.enhancement ||
      type == EditOperationType.upscaling ||
      type == EditOperationType.denoising ||
      type == EditOperationType.smartCrop ||
      type == EditOperationType.autoEnhance ||
      type == EditOperationType.curves ||
      type == EditOperationType.hsl ||
      type == EditOperationType.selectiveColor ||
      type == EditOperationType.editGroup;

  /// Whether this operation uses a mask.
  bool get usesMask =>
      type == EditOperationType.backgroundRemoval ||
      type == EditOperationType.backgroundReplacement ||
      type == EditOperationType.objectRemoval ||
      type == EditOperationType.inpainting ||
      type == EditOperationType.selectiveColor;

  /// Whether this operation requires AI inference.
  bool get requiresAiInference =>
      type == EditOperationType.backgroundRemoval ||
      type == EditOperationType.enhancement ||
      type == EditOperationType.upscaling;

  /// Whether this operation is purely algorithmic (no ML model).
  bool get isAlgorithmic =>
      type == EditOperationType.objectRemoval ||
      type == EditOperationType.inpainting ||
      type == EditOperationType.denoising ||
      type == EditOperationType.smartCrop ||
      type == EditOperationType.backgroundReplacement;

  /// Whether this is a metadata-only operation (no pixel transformation).
  bool get isMetadataOnly =>
      type == EditOperationType.aiAnalysis;

  /// Human-readable summary of this AI operation.
  String get aiSummary {
    return switch (type) {
      EditOperationType.backgroundRemoval => 'Background Removal',
      EditOperationType.backgroundReplacement => 'Background Replacement',
      EditOperationType.objectRemoval => 'Object Removal',
      EditOperationType.inpainting => 'Inpainting',
      EditOperationType.enhancement => 'Enhancement',
      EditOperationType.upscaling => 'Upscale ${upscaleScale}x',
      EditOperationType.denoising => 'Denoise',
      EditOperationType.smartCrop => 'Smart Crop',
      EditOperationType.aiAnalysis => 'AI Analysis',
      EditOperationType.autoEnhance => 'Auto Enhance',
      EditOperationType.curves => 'Curves',
      EditOperationType.hsl => 'HSL',
      EditOperationType.selectiveColor => 'Selective Color',
      EditOperationType.editGroup => groupName.isNotEmpty ? groupName : 'Edit Group',
      _ => '',
    };
  }

  /// Whether this is a geometric operation (crop, rotate, flip, straighten, resize, perspective).
  bool get isGeometric =>
      type == EditOperationType.crop ||
      type == EditOperationType.rotate ||
      type == EditOperationType.flip ||
      type == EditOperationType.straighten ||
      type == EditOperationType.resize ||
      type == EditOperationType.perspective;

  // --- Resize / Perspective getters (Phase 14) ---
  int get resizeWidth => (params['width'] as num?)?.toInt() ?? 0;
  int get resizeHeight => (params['height'] as num?)?.toInt() ?? 0;
  bool get resizeMaintainAspect => (params['maintainAspect'] as bool?) ?? true;
  String get resizeMethod => (params['method'] as String?) ?? 'lanczos';
  bool get isResize => type == EditOperationType.resize;
  bool get isPerspective => type == EditOperationType.perspective;
  Map<String, double> get perspectiveDeltas => {
        'tlX': (params['tlX'] as num?)?.toDouble() ?? 0.0,
        'tlY': (params['tlY'] as num?)?.toDouble() ?? 0.0,
        'trX': (params['trX'] as num?)?.toDouble() ?? 0.0,
        'trY': (params['trY'] as num?)?.toDouble() ?? 0.0,
        'brX': (params['brX'] as num?)?.toDouble() ?? 0.0,
        'brY': (params['brY'] as num?)?.toDouble() ?? 0.0,
        'blX': (params['blX'] as num?)?.toDouble() ?? 0.0,
        'blY': (params['blY'] as num?)?.toDouble() ?? 0.0,
      };

  /// The rotation angle in degrees (for rotate and straighten operations).
  double get degrees => params['degrees'] as double;

  /// Whether the image is flipped horizontally.
  bool get isHorizontalFlip => params['horizontal'] as bool;

  /// Whether the image is flipped vertically.
  bool get isVerticalFlip => params['vertical'] as bool;

  /// Crop rectangle values.
  double get cropLeft => params['left'] as double;
  double get cropTop => params['top'] as double;
  double get cropWidth => params['width'] as double;
  double get cropHeight => params['height'] as double;

  /// Effective rotation from both rotate and straighten operations.
  double get effectiveRotation {
    return switch (type) {
      EditOperationType.rotate => degrees,
      EditOperationType.straighten => degrees,
      _ => 0,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'params': Map<String, dynamic>.from(params),
    };
  }

  factory EditOperation.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String;
    final type = EditOperationType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => throw StateError('Unknown EditOperationType: $typeName'),
    );
    final params = Map<String, dynamic>.from(map['params'] as Map);
    return EditOperation(type: type, params: params);
  }

  EditOperation copyWith({
    EditOperationType? type,
    Map<String, dynamic>? params,
  }) {
    return EditOperation(
      type: type ?? this.type,
      params: params ?? Map<String, dynamic>.from(this.params),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditOperation &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          _mapEquals(params, other.params);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(params.entries));

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Effective crop rectangle after applying all crop operations in a recipe.
class CropRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Full image (no crop).
  factory CropRect.full() =>
      const CropRect(left: 0, top: 0, width: 1, height: 1);

  bool get isFullImage => left == 0 && top == 0 && width == 1 && height == 1;

  /// Convert to pixel coordinates for a given image size.
  ui.Rect toPixels(int imageWidth, int imageHeight) {
    return ui.Rect.fromLTWH(
      left * imageWidth,
      top * imageHeight,
      width * imageWidth,
      height * imageHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CropRect &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}
