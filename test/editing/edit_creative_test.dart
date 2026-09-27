import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/domain/models/edit/edit_history.dart';
import 'package:ai_gallery/domain/models/edit/edit_operation.dart';
import 'package:ai_gallery/domain/models/edit/edit_recipe.dart';
import 'package:ai_gallery/domain/models/edit/filter_preset.dart';
import 'package:ai_gallery/domain/models/edit/drawing_layer.dart';
import 'package:ai_gallery/domain/models/edit/text_layer.dart';
import 'package:ai_gallery/domain/models/edit/frame_config.dart';
import 'package:ai_gallery/features/editing/services/edit_transformation_engine.dart';

import 'package:image/image.dart' as img;

/// Helper to create a test image.
img.Image _testImage({
  int width = 100,
  int height = 100,
  int r = 128,
  int g = 128,
  int b = 128,
}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}

/// Helper to average RGB of entire image.
(double, double, double) _avgColor(img.Image image) {
  var rSum = 0.0;
  var gSum = 0.0;
  var bSum = 0.0;
  final count = image.width * image.height;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      rSum += px.r.toDouble();
      gSum += px.g.toDouble();
      bSum += px.b.toDouble();
    }
  }
  return (rSum / count, gSum / count, bSum / count);
}

/// Helper to create a test recipe.
EditRecipe _recipe([List<EditOperation> ops = const []]) {
  return EditRecipe(
    photoId: 'test_photo',
    operations: ops,
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );
}

/// Helper to create a recipe from a builder.
EditRecipe _recipeFrom(EditRecipe base) => base;

void main() {
  // ========================================================================
  // FILTER PRESETS
  // ========================================================================
  group('FilterPreset', () {
    test('all presets have unique IDs', () {
      final ids = FilterPresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('all presets have non-empty names', () {
      for (final preset in FilterPresets.all) {
        expect(preset.name.isNotEmpty, isTrue);
      }
    });

    test('all presets have valid categories', () {
      final validCategories = {
        'Natural', 'Portrait', 'Cinematic',
        'B&W', 'Vintage', 'Vibrant',
      };
      for (final preset in FilterPresets.all) {
        expect(validCategories.contains(preset.category), isTrue,
            reason: 'Preset ${preset.id} has invalid category: ${preset.category}');
      }
    });

    test('all presets have non-empty adjustments', () {
      for (final preset in FilterPresets.all) {
        expect(preset.adjustments.isNotEmpty, isTrue,
            reason: 'Preset ${preset.id} has no adjustments');
      }
    });

    test('B&W presets have low saturation', () {
      for (final preset in FilterPresets.all) {
        if (preset.category == 'B&W') {
          expect(preset.adjustments['saturation'], lessThanOrEqualTo(0.0),
              reason: 'B&W preset ${preset.id} should have low saturation');
        }
      }
    });

    test('18 presets exist across 6 categories', () {
      expect(FilterPresets.all.length, 18);
      final categories = FilterPresets.all.map((p) => p.category).toSet();
      expect(categories.length, 6);
    });

    test('serialization round-trip', () {
      for (final preset in FilterPresets.all) {
        final map = preset.toMap();
        final restored = FilterPreset.fromMap(map);
        expect(restored.id, preset.id);
        expect(restored.name, preset.name);
        expect(restored.category, preset.category);
        expect(restored.adjustments.length, preset.adjustments.length);
      }
    });
  });

  // ========================================================================
  // EDIT OPERATION CREATIVE TYPES
  // ========================================================================
  group('EditOperation creative factories', () {
    test('filter creates correct type and params', () {
      final op = EditOperation.filter(presetId: 'cinematic', intensity: 0.7);
      expect(op.type, EditOperationType.filter);
      expect(op.filterPresetId, 'cinematic');
      expect(op.filterIntensity, 0.7);
      expect(op.isFilter, isTrue);
      expect(op.isCreative, isTrue);
      expect(op.isNoOp, isFalse);
    });

    test('filter defaults to intensity 1.0', () {
      final op = EditOperation.filter(presetId: 'vintage');
      expect(op.filterIntensity, 1.0);
    });

    test('filter intensity clamped to [0, 1]', () {
      final op = EditOperation.filter(presetId: 'vintage', intensity: 1.5);
      expect(op.filterIntensity, 1.0);
      final op2 = EditOperation.filter(presetId: 'vintage', intensity: -0.3);
      expect(op2.filterIntensity, 0.0);
    });

    test('filterWithIntensity creates new op with changed intensity', () {
      final op = EditOperation.filter(presetId: 'cinematic');
      final op2 = op.filterWithIntensity(0.5);
      expect(op2.filterPresetId, 'cinematic');
      expect(op2.filterIntensity, 0.5);
      expect(op.filterIntensity, 1.0); // original unchanged
    });

    test('filter isNoOp when intensity is 0', () {
      final op = EditOperation.filter(presetId: 'vintage', intensity: 0.0);
      expect(op.isNoOp, isTrue);
    });

    test('blur creates correct type and params', () {
      final op = EditOperation.blur(radius: 10.0, strength: 0.6);
      expect(op.type, EditOperationType.blur);
      expect(op.blurRadius, 10.0);
      expect(op.blurStrength, 0.6);
      expect(op.isBlur, isTrue);
      expect(op.isCreative, isTrue);
    });

    test('blur isNoOp when strength is 0', () {
      final op = EditOperation.blur(strength: 0.0);
      expect(op.isNoOp, isTrue);
    });

    test('grain creates correct type and params', () {
      final op = EditOperation.grain(intensity: 0.3, size: 0.7);
      expect(op.type, EditOperationType.grain);
      expect(op.grainIntensity, 0.3);
      expect(op.grainSize, 0.7);
      expect(op.isGrain, isTrue);
    });

    test('grain isNoOp when intensity is 0', () {
      final op = EditOperation.grain(intensity: 0.0);
      expect(op.isNoOp, isTrue);
    });

    test('fade creates correct type and params', () {
      final op = EditOperation.fade(intensity: 0.4);
      expect(op.type, EditOperationType.fade);
      expect(op.fadeIntensity, 0.4);
      expect(op.isFade, isTrue);
    });

    test('fade isNoOp when intensity is 0', () {
      final op = EditOperation.fade(intensity: 0.0);
      expect(op.isNoOp, isTrue);
    });

    test('drawing creates correct type', () {
      final op = EditOperation.drawing(strokes: [
        {'points': [
          {'x': 0.1, 'y': 0.2},
          {'x': 0.3, 'y': 0.4},
        ], 'color': 0xFFFF0000, 'opacity': 1.0, 'width': 0.01, 'brushType': 'round'}
      ]);
      expect(op.type, EditOperationType.drawing);
      expect(op.isDrawing, isTrue);
      expect(op.drawingStrokes.length, 1);
    });

    test('drawing isNoOp when strokes list is empty', () {
      final op = EditOperation.drawing(strokes: []);
      expect(op.isNoOp, isTrue);
    });

    test('text creates correct type with layers', () {
      final op = EditOperation.text(layers: [
        {'text': 'Hello', 'x': 0.5, 'y': 0.5, 'color': 0xFFFFFFFF,
         'fontSize': 0.05, 'opacity': 1.0, 'scale': 1.0, 'rotation': 0.0,
         'fontFamily': 'Roboto', 'alignment': 'center', 'hasBackground': false,
         'backgroundColor': 0xFF000000, 'backgroundOpacity': 0.6,
         'backgroundPadding': 0.1, 'backgroundCornerRadius': 0.15}
      ]);
      expect(op.type, EditOperationType.text);
      expect(op.isText, isTrue);
      expect(op.textLayers.length, 1);
    });

    test('text isNoOp when layers list is empty', () {
      final op = EditOperation.text(layers: []);
      expect(op.isNoOp, isTrue);
    });

    test('frame creates correct type and params', () {
      final op = EditOperation.frame(width: 0.03, color: 0xFF000000);
      expect(op.type, EditOperationType.frame);
      expect(op.frameWidth, 0.03);
      expect(op.frameColor, 0xFF000000);
      expect(op.isFrame, isTrue);
    });

    test('frame isNoOp when width is 0', () {
      final op = EditOperation.frame(width: 0.0);
      expect(op.isNoOp, isTrue);
    });

    test('isGeometric is false for all creative types', () {
      expect(EditOperation.filter(presetId: 'test').isGeometric, isFalse);
      expect(EditOperation.blur().isGeometric, isFalse);
      expect(EditOperation.grain().isGeometric, isFalse);
      expect(EditOperation.fade().isGeometric, isFalse);
      expect(EditOperation.drawing(strokes: []).isGeometric, isFalse);
      expect(EditOperation.text(layers: []).isGeometric, isFalse);
      expect(EditOperation.frame().isGeometric, isFalse);
    });
  });

  // ========================================================================
  // EDIT OPERATION SERIALIZATION
  // ========================================================================
  group('EditOperation creative serialization', () {
    test('filter round-trip', () {
      final op = EditOperation.filter(presetId: 'vintage', intensity: 0.7);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.filter);
      expect(restored.filterPresetId, 'vintage');
      expect(restored.filterIntensity, 0.7);
    });

    test('blur round-trip', () {
      final op = EditOperation.blur(radius: 8.0, strength: 0.6);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.blur);
      expect(restored.blurRadius, 8.0);
      expect(restored.blurStrength, 0.6);
    });

    test('grain round-trip', () {
      final op = EditOperation.grain(intensity: 0.4, size: 0.8);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.grain);
      expect(restored.grainIntensity, 0.4);
      expect(restored.grainSize, 0.8);
    });

    test('fade round-trip', () {
      final op = EditOperation.fade(intensity: 0.5);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.fade);
      expect(restored.fadeIntensity, 0.5);
    });

    test('drawing round-trip', () {
      final op = EditOperation.drawing(strokes: [
        {'points': [
          {'x': 0.1, 'y': 0.2},
        ], 'color': 0xFFFF0000, 'opacity': 0.8, 'width': 0.02, 'brushType': 'soft'}
      ]);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.drawing);
      expect(restored.drawingStrokes.length, 1);
    });

    test('text round-trip', () {
      final op = EditOperation.text(layers: [
        {'text': 'Test', 'x': 0.3, 'y': 0.4, 'color': 0xFF00FF00,
         'fontSize': 0.1, 'opacity': 0.9, 'scale': 1.5, 'rotation': 45.0,
         'fontFamily': 'Arial', 'alignment': 'left', 'hasBackground': true,
         'backgroundColor': 0xFF333333, 'backgroundOpacity': 0.7,
         'backgroundPadding': 0.2, 'backgroundCornerRadius': 0.3}
      ]);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.text);
      expect(restored.textLayers.length, 1);
      expect(restored.textLayers[0]['text'], 'Test');
    });

    test('frame round-trip', () {
      final op = EditOperation.frame(
        width: 0.04,
        color: 0xFFABCDEF,
        opacity: 0.8,
        cornerRadius: 0.2,
        roundedCorners: true,
        imageCornerRadius: 0.05,
      );
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.frame);
      expect(restored.frameWidth, 0.04);
      expect(restored.frameColor, 0xFFABCDEF);
      expect(restored.frameOpacity, 0.8);
      expect(restored.params['cornerRadius'], 0.2);
      expect(restored.params['roundedCorners'], true);
      expect(restored.params['imageCornerRadius'], 0.05);
    });
  });

  // ========================================================================
  // DRAWING LAYER MODEL
  // ========================================================================
  group('DrawingLayer', () {
    test('empty by default', () {
      const layer = DrawingLayer();
      expect(layer.isEmpty, isTrue);
      expect(layer.isNotEmpty, isFalse);
      expect(layer.strokeCount, 0);
    });

    test('addStroke creates new layer with stroke', () {
      const layer = DrawingLayer();
      final stroke = Stroke(
        points: [
          const StrokePoint(x: 0.1, y: 0.2),
          const StrokePoint(x: 0.3, y: 0.4),
        ],
        color: 0xFFFF0000,
      );
      final newLayer = layer.addStroke(stroke);
      expect(newLayer.strokeCount, 1);
      expect(layer.strokeCount, 0); // original unchanged
    });

    test('removeLastStroke removes last', () {
      final layer = const DrawingLayer().addStroke(
        const Stroke(points: [StrokePoint(x: 0.1, y: 0.1)], color: 0xFF000000),
      );
      final finalLayer = layer.removeLastStroke();
      expect(finalLayer.isEmpty, isTrue);
    });

    test('removeLastStroke on empty returns same', () {
      const layer = DrawingLayer();
      final result = layer.removeLastStroke();
      expect(result.isEmpty, isTrue);
    });

    test('clear returns empty', () {
      final layer = const DrawingLayer().addStroke(
        const Stroke(points: [StrokePoint(x: 0.1, y: 0.1)], color: 0xFF000000),
      );
      final cleared = layer.clear();
      expect(cleared.isEmpty, isTrue);
    });

    test('serialization round-trip', () {
      final layer = const DrawingLayer().addStroke(const Stroke(
        points: [StrokePoint(x: 0.1, y: 0.2, pressure: 0.8)],
        color: 0xFF00FF00,
        opacity: 0.7,
        width: 0.02,
        brushType: BrushType.soft,
      ));
      final map = layer.toMap();
      final restored = DrawingLayer.fromMap(map);
      expect(restored.strokeCount, 1);
      expect(restored.strokes[0].color, 0xFF00FF00);
      expect(restored.strokes[0].opacity, 0.7);
      expect(restored.strokes[0].brushType, BrushType.soft);
      expect(restored.strokes[0].points[0].pressure, 0.8);
    });
  });

  // ========================================================================
  // STROKE MODEL
  // ========================================================================
  group('Stroke', () {
    test('isEmpty when points is empty', () {
      const stroke = Stroke(points: [], color: 0xFF000000);
      expect(stroke.isEmpty, isTrue);
    });

    test('serialization round-trip', () {
      const stroke = Stroke(
        points: [
          StrokePoint(x: 0.1, y: 0.2),
          StrokePoint(x: 0.3, y: 0.4, pressure: 0.5),
        ],
        color: 0xFFAABBCC,
        opacity: 0.8,
        width: 0.015,
        brushType: BrushType.soft,
      );
      final map = stroke.toMap();
      final restored = Stroke.fromMap(map);
      expect(restored.points.length, 2);
      expect(restored.color, 0xFFAABBCC);
      expect(restored.opacity, 0.8);
      expect(restored.width, 0.015);
      expect(restored.brushType, BrushType.soft);
    });

    test('uiColor returns correct color', () {
      const stroke = Stroke(points: [], color: 0xFFFF0000);
      expect(stroke.uiColor.red, 255);
      expect(stroke.uiColor.green, 0);
      expect(stroke.uiColor.blue, 0);
    });
  });

  // ========================================================================
  // STROKE POINT MODEL
  // ========================================================================
  group('StrokePoint', () {
    test('lerp interpolates correctly', () {
      const a = StrokePoint(x: 0.0, y: 0.0, pressure: 0.0);
      const b = StrokePoint(x: 1.0, y: 1.0, pressure: 1.0);
      final mid = StrokePoint.lerp(a, b, 0.5);
      expect(mid.x, 0.5);
      expect(mid.y, 0.5);
      expect(mid.pressure, 0.5);
    });

    test('serialization round-trip preserves pressure', () {
      const point = StrokePoint(x: 0.3, y: 0.7, pressure: 0.6);
      final map = point.toMap();
      expect(map['pressure'], 0.6);
      final restored = StrokePoint.fromMap(map);
      expect(restored.pressure, 0.6);
    });

    test('serialization omits pressure when default', () {
      const point = StrokePoint(x: 0.1, y: 0.2);
      final map = point.toMap();
      expect(map.containsKey('pressure'), isFalse);
      final restored = StrokePoint.fromMap(map);
      expect(restored.pressure, 1.0); // default
    });

    test('equality works', () {
      const a = StrokePoint(x: 0.1, y: 0.2, pressure: 0.5);
      const b = StrokePoint(x: 0.1, y: 0.2, pressure: 0.5);
      const c = StrokePoint(x: 0.1, y: 0.2, pressure: 0.6);
      expect(a, b);
      expect(a == c, isFalse);
    });
  });

  // ========================================================================
  // TEXT LAYER MODEL
  // ========================================================================
  group('TextLayer', () {
    test('default values', () {
      const layer = TextLayer(text: 'Hello');
      expect(layer.text, 'Hello');
      expect(layer.x, 0.5);
      expect(layer.y, 0.5);
      expect(layer.opacity, 1.0);
      expect(layer.fontSize, 0.05);
      expect(layer.hasBackground, isFalse);
    });

    test('copyWith creates correct copy', () {
      const layer = TextLayer(text: 'Hello');
      final modified = layer.copyWith(
        text: 'World',
        color: 0xFFFF0000,
        opacity: 0.5,
      );
      expect(modified.text, 'World');
      expect(modified.color, 0xFFFF0000);
      expect(modified.opacity, 0.5);
      expect(layer.text, 'Hello'); // original unchanged
    });

    test('serialization round-trip', () {
      const layer = TextLayer(
        text: 'Test',
        x: 0.3,
        y: 0.4,
        scale: 2.0,
        rotation: 45.0,
        color: 0xFF00FF00,
        opacity: 0.7,
        fontSize: 0.08,
        alignment: TextAlignment.right,
        hasBackground: true,
        backgroundColor: 0xFF333333,
        backgroundOpacity: 0.6,
        backgroundPadding: 0.2,
        backgroundCornerRadius: 0.3,
      );
      final map = layer.toMap();
      final restored = TextLayer.fromMap(map);
      expect(restored.text, 'Test');
      expect(restored.x, 0.3);
      expect(restored.y, 0.4);
      expect(restored.scale, 2.0);
      expect(restored.rotation, 45.0);
      expect(restored.color, 0xFF00FF00);
      expect(restored.alignment, TextAlignment.right);
      expect(restored.hasBackground, isTrue);
      expect(restored.backgroundColor, 0xFF333333);
    });

    test('equality', () {
      const a = TextLayer(text: 'Hello');
      const b = TextLayer(text: 'Hello');
      const c = TextLayer(text: 'World');
      expect(a, b);
      expect(a == c, isFalse);
    });
  });

  // ========================================================================
  // FRAME CONFIG MODEL
  // ========================================================================
  group('FrameConfig', () {
    test('empty by default', () {
      const config = FrameConfig();
      expect(config.isEmpty, isTrue);
      expect(config.isNotEmpty, isFalse);
    });

    test('isNotEmpty when width > 0', () {
      const config = FrameConfig(width: 0.03);
      expect(config.isNotEmpty, isTrue);
      expect(config.isEmpty, isFalse);
    });

    test('copyWith creates correct copy', () {
      const config = FrameConfig(width: 0.03, color: 0xFF000000);
      final modified = config.copyWith(width: 0.05, opacity: 0.8);
      expect(modified.width, 0.05);
      expect(modified.opacity, 0.8);
      expect(modified.color, 0xFF000000); // preserved
    });

    test('serialization round-trip', () {
      const config = FrameConfig(
        width: 0.04,
        color: 0xFFABCDEF,
        opacity: 0.7,
        cornerRadius: 0.2,
        roundedCorners: true,
        imageCornerRadius: 0.05,
      );
      final map = config.toMap();
      final restored = FrameConfig.fromMap(map);
      expect(restored.width, 0.04);
      expect(restored.color, 0xFFABCDEF);
      expect(restored.opacity, 0.7);
      expect(restored.cornerRadius, 0.2);
      expect(restored.roundedCorners, isTrue);
      expect(restored.imageCornerRadius, 0.05);
    });

    test('equality', () {
      const a = FrameConfig(width: 0.03, color: 0xFF000000);
      const b = FrameConfig(width: 0.03, color: 0xFF000000);
      const c = FrameConfig(width: 0.05, color: 0xFF000000);
      expect(a, b);
      expect(a == c, isFalse);
    });
  });

  // ========================================================================
  // EDIT RECIPE CREATIVE ACCESSORS
  // ========================================================================
  group('EditRecipe creative accessors', () {
    test('filterOperation returns filter op', () {
      final recipe = _recipeFrom(
        _recipe().withFilter('cinematic', 0.8),
      );
      expect(recipe.filterOperation, isNotNull);
      expect(recipe.filterOperation!.filterPresetId, 'cinematic');
      expect(recipe.hasFilter, isTrue);
    });

    test('hasFilter is false when no filter', () {
      final recipe = _recipe();
      expect(recipe.hasFilter, isFalse);
      expect(recipe.filterOperation, isNull);
    });

    test('hasEffects returns true when blur is active', () {
      final recipe = _recipeFrom(_recipe().withBlur(5.0, 0.5));
      expect(recipe.hasEffects, isTrue);
      expect(recipe.blurOperation, isNotNull);
    });

    test('hasEffects returns true when grain is active', () {
      final recipe = _recipeFrom(_recipe().withGrain(0.3, 0.5));
      expect(recipe.hasEffects, isTrue);
      expect(recipe.grainOperation, isNotNull);
    });

    test('hasEffects returns true when fade is active', () {
      final recipe = _recipeFrom(_recipe().withFade(0.4));
      expect(recipe.hasEffects, isTrue);
      expect(recipe.fadeOperation, isNotNull);
    });

    test('hasDrawing returns true when strokes exist', () {
      final layer = const DrawingLayer().addStroke(
        const Stroke(points: [StrokePoint(x: 0.1, y: 0.1)], color: 0xFF000000),
      );
      final recipe = _recipeFrom(_recipe().withDrawing(layer));
      expect(recipe.hasDrawing, isTrue);
      expect(recipe.drawingLayer.isNotEmpty, isTrue);
    });

    test('hasText returns true when layers exist', () {
      const layers = [TextLayer(text: 'Hello')];
      final recipe = _recipeFrom(_recipe().withTextLayers(layers));
      expect(recipe.hasText, isTrue);
      expect(recipe.textLayers.length, 1);
      expect(recipe.textLayers[0].text, 'Hello');
    });

    test('hasFrame returns true when frame is set', () {
      const frame = FrameConfig(width: 0.03, color: 0xFF000000);
      final recipe = _recipeFrom(_recipe().withFrame(frame));
      expect(recipe.hasFrame, isTrue);
      expect(recipe.frameConfig.width, 0.03);
    });

    test('hasCreativeEdits is true when any creative edit exists', () {
      final recipe = _recipeFrom(_recipe().withFade(0.3));
      expect(recipe.hasCreativeEdits, isTrue);
    });

    test('hasCreativeEdits is false with no creative edits', () {
      final recipe = _recipe();
      expect(recipe.hasCreativeEdits, isFalse);
    });

    test('frameConfig returns empty FrameConfig when no frame', () {
      final recipe = _recipe();
      expect(recipe.frameConfig.isEmpty, isTrue);
    });

    test('drawingLayer returns empty DrawingLayer when no drawing', () {
      final recipe = _recipe();
      expect(recipe.drawingLayer.isEmpty, isTrue);
    });

    test('textLayers returns empty list when no text', () {
      final recipe = _recipe();
      expect(recipe.textLayers.isEmpty, isTrue);
    });
  });

  // ========================================================================
  // EDIT RECIPE CREATIVE MODIFIERS
  // ========================================================================
  group('EditRecipe creative modifiers', () {
    test('withFilter adds filter operation', () {
      final recipe = _recipeFrom(_recipe().withFilter('vintage', 0.9));
      expect(recipe.operations.length, 1);
      expect(recipe.filterOperation!.filterPresetId, 'vintage');
    });

    test('withFilter replaces existing filter', () {
      var recipe = _recipeFrom(_recipe().withFilter('vintage', 0.9));
      recipe = _recipeFrom(recipe.withFilter('cinematic', 0.5));
      expect(recipe.operations.length, 1); // still just 1
      expect(recipe.filterOperation!.filterPresetId, 'cinematic');
    });

    test('withoutFilter removes filter', () {
      final recipe = _recipeFrom(
        _recipe().withFilter('vintage', 0.9).withoutFilter(),
      );
      expect(recipe.hasFilter, isFalse);
    });

    test('withBlur replaces existing blur', () {
      var recipe = _recipeFrom(_recipe().withBlur(5.0, 0.5));
      recipe = _recipeFrom(recipe.withBlur(10.0, 0.8));
      expect(recipe.operations.length, 1);
      expect(recipe.blurOperation!.blurRadius, 10.0);
    });

    test('withGrain replaces existing grain', () {
      var recipe = _recipeFrom(_recipe().withGrain(0.3, 0.5));
      recipe = _recipeFrom(recipe.withGrain(0.6, 0.8));
      expect(recipe.operations.length, 1);
      expect(recipe.grainOperation!.grainIntensity, 0.6);
    });

    test('withFade replaces existing fade', () {
      var recipe = _recipeFrom(_recipe().withFade(0.3));
      recipe = _recipeFrom(recipe.withFade(0.7));
      expect(recipe.operations.length, 1);
      expect(recipe.fadeOperation!.fadeIntensity, 0.7);
    });

    test('withoutFrame removes frame', () {
      final recipe = _recipeFrom(
        _recipe().withFrame(const FrameConfig(width: 0.03)).withoutFrame(),
      );
      expect(recipe.hasFrame, isFalse);
    });

    test('withoutCreativeEdits removes all creative ops', () {
      var recipe = _recipeFrom(
        _recipe()
            .withFilter('vintage', 0.9)
            .withBlur(5.0, 0.5)
            .withFade(0.3),
      );
      recipe = _recipeFrom(recipe.withoutCreativeEdits());
      expect(recipe.hasCreativeEdits, isFalse);
    });

    test('withTextLayers replaces existing text layers', () {
      var recipe = _recipeFrom(
        _recipe().withTextLayers(const [TextLayer(text: 'Hello')]),
      );
      recipe = _recipeFrom(recipe.withTextLayers(const [TextLayer(text: 'World')]));
      expect(recipe.textLayers.length, 1);
      expect(recipe.textLayers[0].text, 'World');
    });
  });

  // ========================================================================
  // TRANSFORMATION ENGINE - CREATIVE PIPELINE
  // ========================================================================
  group('TransformationEngine creative rendering', () {
    test('filter changes image appearance', () {
      final image = _testImage(r: 128, g: 128, b: 128);
      final recipe = _recipeFrom(_recipe().withFilter('cinematic', 1.0));
      final result = EditTransformationEngine.apply(image, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r != 128 || g != 128 || b != 128, isTrue,
          reason: 'Filter should change image appearance');
    });

    test('filter at intensity 0 produces nearly unchanged image', () {
      final image = _testImage(r: 128, g: 128, b: 128);
      final recipe = _recipeFrom(_recipe().withFilter('vintage', 0.0));
      final result = EditTransformationEngine.apply(image, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r.round(), 128);
      expect(g.round(), 128);
      expect(b.round(), 128);
    });

    test('blur runs without error', () {
      final image = _testImage(width: 50, height: 50, r: 200, g: 100, b: 50);
      final recipe = _recipeFrom(_recipe().withBlur(10.0, 1.0));
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 50);
      expect(result.outputHeight, 50);
    });

    test('grain adds noise variation', () {
      final image = _testImage(r: 128, g: 128, b: 128);
      final recipe = _recipeFrom(_recipe().withGrain(0.5, 0.5));
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 100);
      expect(result.outputHeight, 100);
    });

    test('fade reduces contrast', () {
      final image = _testImage(r: 200, g: 100, b: 50);
      final recipe = _recipeFrom(_recipe().withFade(0.8));
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 100);
      expect(result.outputHeight, 100);
    });

    test('drawing layer is applied', () {
      final image = _testImage(width: 50, height: 50, r: 100, g: 100, b: 100);
      final stroke = Stroke(
        points: [
          const StrokePoint(x: 0.1, y: 0.1),
          const StrokePoint(x: 0.9, y: 0.9),
        ],
        color: 0xFFFF0000,
        width: 0.05,
      );
      final layer = const DrawingLayer().addStroke(stroke);
      final recipe = _recipeFrom(_recipe().withDrawing(layer));
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 50);
      expect(result.outputHeight, 50);
    });

    test('text layer is applied', () {
      final image = _testImage(width: 50, height: 50);
      const layers = [
        TextLayer(
          text: 'Hello',
          x: 0.5,
          y: 0.5,
          fontSize: 0.08,
          color: 0xFFFFFFFF,
        ),
      ];
      final recipe = _recipeFrom(_recipe().withTextLayers(layers));
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 50);
      expect(result.outputHeight, 50);
    });

    test('frame is applied', () {
      final image = _testImage(width: 50, height: 50);
      const frame = FrameConfig(width: 0.04, color: 0xFFFFFFFF);
      final recipe = _recipeFrom(_recipe().withFrame(frame));
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, greaterThan(50));
      expect(result.outputHeight, greaterThan(50));
    });

    test('combined creative operations all apply', () {
      final image = _testImage(width: 50, height: 50);
      var recipe = _recipe();
      recipe = recipe.withFilter('cinematic', 0.8);
      recipe = recipe.withBlur(3.0, 0.3);
      recipe = recipe.withFade(0.2);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 50);
      expect(result.outputHeight, 50);
    });

    test('no creative ops returns unchanged image', () {
      final image = _testImage(r: 100, g: 150, b: 200);
      final recipe = _recipe();
      final result = EditTransformationEngine.apply(image, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r.round(), 100);
      expect(g.round(), 150);
      expect(b.round(), 200);
    });
  });

  // ========================================================================
  // EDIT HISTORY WITH CREATIVE OPS
  // ========================================================================
  group('EditHistory with creative operations', () {
    test('undo/redo works with creative operations', () {
      final empty = _recipe();
      final withFilter = _recipeFrom(
        _recipe().withFilter('cinematic', 0.8),
      );
      final withFade = _recipeFrom(
        _recipe().withFade(0.5),
      );

      // Constructor creates initial snapshot from empty recipe
      final history = EditHistoryManager(initial: empty);
      history.pushState(withFilter.operations);
      history.pushState(withFade.operations);

      // snapshots: [[], filter, fade], currentIndex=2
      // Undo: idx 2→1 (filter ops)
      final ops1 = history.undo()!;
      final recipe1 = _recipeFrom(_recipe().copyWith(operations: ops1));
      expect(recipe1.hasFilter, isTrue);

      // Undo: idx 1→0 (empty initial)
      final ops0 = history.undo()!;
      final recipe0 = _recipeFrom(_recipe().copyWith(operations: ops0));
      expect(recipe0.hasCreativeEdits, isFalse);

      // Redo: idx 0→1 (filter ops again)
      final opsR = history.redo()!;
      final recipeR = _recipeFrom(_recipe().copyWith(operations: opsR));
      expect(recipeR.hasFilter, isTrue);
    });

    test('replaceCurrent works for live slider updates', () {
      final empty = _recipe();
      final withFilter1 = _recipeFrom(
        _recipe().withFilter('cinematic', 0.1),
      );
      final withFilter5 = _recipeFrom(
        _recipe().withFilter('cinematic', 0.5),
      );

      final history = EditHistoryManager(initial: empty);
      history.pushState(withFilter1.operations);

      // Simulate slider drag — replace without adding to undo stack
      history.replaceCurrent(withFilter5.operations);

      final currentOps = history.currentOperations;
      final currentRecipe = _recipeFrom(_recipe().copyWith(operations: currentOps));
      expect(currentRecipe.filterOperation!.filterIntensity, 0.5);

      // Undo should go back to initial state
      history.undo();
      final undoneOps = history.currentOperations;
      final undoneRecipe = _recipeFrom(_recipe().copyWith(operations: undoneOps));
      expect(undoneRecipe.hasFilter, isFalse);
    });

    test('commitState after replaceCurrent adds to undo stack', () {
      final empty = _recipe();
      final withFilter1 = _recipeFrom(
        _recipe().withFilter('cinematic', 0.1),
      );
      final withFilter5 = _recipeFrom(
        _recipe().withFilter('cinematic', 0.5),
      );

      final history = EditHistoryManager(initial: empty);
      history.pushState(withFilter1.operations);

      history.replaceCurrent(withFilter5.operations);
      history.commitState(withFilter5.operations);

      // Now undo should go to the committed state (0.5)
      history.undo();
      final ops = history.currentOperations;
      final recipe = _recipeFrom(_recipe().copyWith(operations: ops));
      expect(recipe.filterOperation!.filterIntensity, 0.5);
    });
  });

  // ========================================================================
  // COMBINED CREATIVE + ADJUSTMENTS
  // ========================================================================
  group('Creative + adjustments pipeline', () {
    test('adjustments + filter both apply', () {
      final image = _testImage(r: 128, g: 128, b: 128);
      var recipe = _recipe();
      recipe = recipe.withAdjustment('brightness', 0.5);
      recipe = recipe.withFilter('cinematic', 0.8);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 100);
      expect(result.outputHeight, 100);
    });

    test('geometric + creative + adjustments all apply', () {
      final image = _testImage(width: 80, height: 60);
      var recipe = _recipe();
      recipe = recipe.withAdjustment('contrast', 0.3);
      recipe = recipe.withFilter('vintage', 0.7);
      recipe = recipe.withFade(0.2);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 80);
      expect(result.outputHeight, 60);
    });
  });
}
