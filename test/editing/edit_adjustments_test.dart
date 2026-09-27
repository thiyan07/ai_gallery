import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/domain/models/edit/edit_history.dart';
import 'package:ai_gallery/domain/models/edit/edit_operation.dart';
import 'package:ai_gallery/domain/models/edit/edit_recipe.dart';
import 'package:ai_gallery/features/editing/services/edit_transformation_engine.dart';

import 'package:image/image.dart' as img;

/// Helper to create a test image of a given size and color.
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

/// Helper to create a gradient test image (left-to-right brightness ramp).
img.Image _gradientImage({int width = 100, int height = 100}) {
  final image = img.Image(width: width, height: height);
  for (var x = 0; x < width; x++) {
    final val = (x * 255 ~/ (width - 1)).clamp(0, 255);
    for (var y = 0; y < height; y++) {
      image.setPixelRgba(x, y, val, val, val, 255);
    }
  }
  return image;
}

/// Helper to average RGB of center pixel.
(double, double, double) _centerPixel(img.Image image) {
  final px = image.getPixel(image.width ~/ 2, image.height ~/ 2);
  return (px.r.toDouble(), px.g.toDouble(), px.b.toDouble());
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

void main() {
  // ==========================================================================
  // EditOperation ADJUSTMENT tests
  // ==========================================================================
  group('EditOperation.adjustment', () {
    test('creates with all defaults neutral', () {
      final op = EditOperation.adjustment();
      expect(op.type, EditOperationType.adjustment);
      expect(op.isAdjustment, isTrue);
      expect(op.exposure, 0.0);
      expect(op.brightness, 0.0);
      expect(op.contrast, 0.0);
      expect(op.highlights, 0.0);
      expect(op.shadows, 0.0);
      expect(op.whites, 0.0);
      expect(op.blacks, 0.0);
      expect(op.saturation, 0.0);
      expect(op.vibrance, 0.0);
      expect(op.temperature, 0.0);
      expect(op.tint, 0.0);
      expect(op.sharpness, 0.0);
      expect(op.clarity, 0.0);
      expect(op.vignette, 0.0);
    });

    test('isNoOp when all values are 0', () {
      final op = EditOperation.adjustment();
      expect(op.isNoOp, isTrue);
      expect(op.hasNonNeutralAdjustments, isFalse);
    });

    test('isNoOp when some values are non-zero', () {
      final op = EditOperation.adjustment(exposure: 0.5);
      expect(op.isNoOp, isFalse);
      expect(op.hasNonNeutralAdjustments, isTrue);
    });

    test('adjustmentWith creates new op with one value changed', () {
      final op = EditOperation.adjustment();
      final updated = op.adjustmentWith('exposure', 0.7);
      expect(updated.exposure, 0.7);
      expect(updated.brightness, 0.0); // unchanged
      expect(updated.isNoOp, isFalse);
    });

    test('adjustmentWith clamps values to [-1, 1]', () {
      final op = EditOperation.adjustment();
      final overMax = op.adjustmentWith('exposure', 2.0);
      expect(overMax.exposure, 1.0);
      final underMin = op.adjustmentWith('exposure', -2.0);
      expect(underMin.exposure, -1.0);
    });

    test('adjustmentValues returns all values', () {
      final op = EditOperation.adjustment(exposure: 0.5, saturation: -0.3);
      final values = op.adjustmentValues;
      expect(values['exposure'], 0.5);
      expect(values['saturation'], -0.3);
      expect(values.length, 14);
    });

    test('adjustmentSummary lists non-neutral values', () {
      final op = EditOperation.adjustment(exposure: 0.5, saturation: -0.3);
      final summary = op.adjustmentSummary;
      expect(summary, contains('Exposure'));
      expect(summary, contains('Saturation'));
      expect(summary, isNot(contains('Brightness')));
    });

    test('adjustmentSummary is empty for non-adjustment op', () {
      final op = EditOperation.rotate(degrees: 90);
      expect(op.adjustmentSummary, isEmpty);
    });

    test('serialization round-trip', () {
      final op = EditOperation.adjustment(
        exposure: 0.5,
        brightness: -0.3,
        contrast: 0.8,
        temperature: 0.2,
      );
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.type, EditOperationType.adjustment);
      expect(restored.exposure, 0.5);
      expect(restored.brightness, -0.3);
      expect(restored.contrast, 0.8);
      expect(restored.temperature, 0.2);
    });
  });

  // ==========================================================================
  // AdjustmentDefaults tests
  // ==========================================================================
  group('AdjustmentDefaults', () {
    test('all values are 0.0', () {
      for (final entry in AdjustmentDefaults.all.entries) {
        expect(entry.value, 0.0, reason: '${entry.key} should default to 0');
      }
    });

    test('pipeline order has all 14 keys', () {
      expect(AdjustmentDefaults.pipelineOrder.length, 14);
    });

    test('clampValue works', () {
      expect(AdjustmentDefaults.clampValue(0.5), 0.5);
      expect(AdjustmentDefaults.clampValue(2.0), 1.0);
      expect(AdjustmentDefaults.clampValue(-2.0), -1.0);
    });

    test('UI groups cover all 14 adjustments', () {
      final all = [
        ...AdjustmentDefaults.lightGroup,
        ...AdjustmentDefaults.colorGroup,
        ...AdjustmentDefaults.detailGroup,
      ];
      expect(all.length, 14);
      for (final key in AdjustmentDefaults.all.keys) {
        expect(all, contains(key), reason: '$key missing from UI groups');
      }
    });
  });

  // ==========================================================================
  // EditRecipe adjustment integration tests
  // ==========================================================================
  group('EditRecipe adjustments', () {
    test('adjustmentOperation returns null when no adjustment op', () {
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.rotate(degrees: 90)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(recipe.adjustmentOperation, isNull);
      expect(recipe.hasAdjustments, isFalse);
    });

    test('adjustmentOperation returns the adjustment op', () {
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.rotate(degrees: 90),
          EditOperation.adjustment(exposure: 0.5),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(recipe.adjustmentOperation, isNotNull);
      expect(recipe.hasAdjustments, isTrue);
    });

    test('withAdjustment adds new adjustment op', () {
      final recipe = EditRecipe(
        photoId: 'test',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final updated = recipe.withAdjustment('exposure', 0.5);
      expect(updated.adjustmentValue('exposure'), 0.5);
      expect(updated.adjustmentValue('brightness'), 0.0);
    });

    test('withAdjustment replaces existing adjustment value', () {
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.adjustment(exposure: 0.5, contrast: 0.3),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final updated = recipe.withAdjustment('exposure', -0.2);
      expect(updated.adjustmentValue('exposure'), -0.2);
      expect(updated.adjustmentValue('contrast'), 0.3); // preserved
    });

    test('resetAdjustment sets value to 0', () {
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.adjustment(exposure: 0.5, contrast: 0.3),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final updated = recipe.resetAdjustment('exposure');
      expect(updated.adjustmentValue('exposure'), 0.0);
      expect(updated.adjustmentValue('contrast'), 0.3);
    });

    test('resetAllAdjustments removes adjustment op entirely', () {
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.rotate(degrees: 90),
          EditOperation.adjustment(exposure: 0.5),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final updated = recipe.resetAllAdjustments();
      expect(updated.hasAdjustments, isFalse);
      // Rotate should remain
      expect(updated.operations.length, 1);
      expect(updated.operations.first.type, EditOperationType.rotate);
    });

    test('serialization round-trip with adjustments', () {
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.rotate(degrees: 90),
          EditOperation.adjustment(exposure: 0.5, saturation: -0.3),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final json = recipe.operationsToJson();
      final restored = EditRecipe.operationsFromJson(json);
      expect(restored.length, 2);
      expect(restored[0].type, EditOperationType.rotate);
      expect(restored[1].type, EditOperationType.adjustment);
      expect(restored[1].exposure, 0.5);
      expect(restored[1].saturation, -0.3);
    });
  });

  // ==========================================================================
  // EditHistoryManager tests
  // ==========================================================================
  group('EditHistoryManager', () {
    test('replaceCurrent does not add new undo entry', () {
      final mgr = EditHistoryManager();
      mgr.pushState([EditOperation.rotate(degrees: 90)]);
      final before = mgr.undoCount;
      mgr.replaceCurrent([EditOperation.rotate(degrees: 180)]);
      expect(mgr.undoCount, before); // unchanged
      expect(mgr.currentOperations.first.degrees, 180);
    });

    test('commitState adds new undo entry', () {
      final mgr = EditHistoryManager();
      mgr.pushState([EditOperation.rotate(degrees: 90)]);
      final before = mgr.undoCount;
      mgr.commitState([EditOperation.rotate(degrees: 180)]);
      expect(mgr.undoCount, before + 1);
    });

    test('coalesceState groups rapid changes', () {
      final mgr = EditHistoryManager();
      mgr.pushState([EditOperation.adjustment(exposure: 0.0)]);
      final before = mgr.undoCount;
      // First coalesce adds entry
      mgr.coalesceState([EditOperation.adjustment(exposure: 0.1)]);
      expect(mgr.undoCount, before + 1);
      // Second coalesce replaces current
      mgr.coalesceState([EditOperation.adjustment(exposure: 0.2)]);
      expect(mgr.undoCount, before + 1); // same count
      expect(
        (mgr.currentOperations.first as EditOperation).exposure,
        0.2,
      );
    });

    test('pushState after coalesce breaks the group', () {
      final mgr = EditHistoryManager();
      mgr.pushState([]);
      mgr.coalesceState([EditOperation.adjustment(exposure: 0.1)]);
      mgr.coalesceState([EditOperation.adjustment(exposure: 0.2)]);
      final before = mgr.undoCount;
      mgr.pushState([EditOperation.rotate(degrees: 90)]);
      expect(mgr.undoCount, before + 1);
    });

    test('undo after replaceCurrent restores previous state', () {
      final mgr = EditHistoryManager();
      mgr.pushState([EditOperation.adjustment(exposure: 0.0)]);
      mgr.pushState([EditOperation.adjustment(exposure: 0.5)]);
      mgr.replaceCurrent([EditOperation.adjustment(exposure: 0.7)]);
      final undone = mgr.undo();
      expect(undone, isNotNull);
      // replaceCurrent modified snapshot[1], so undo goes to snapshot[0] (0.0)
      expect((undone!.first as EditOperation).exposure, 0.0);
    });
  });

  // ==========================================================================
  // EditTransformationEngine adjustment rendering tests
  // ==========================================================================
  group('EditTransformationEngine adjustments', () {
    test('neutral adjustments produce no change', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment()],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      // Empty recipe means no changes
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r, closeTo(128.0, 1.0));
      expect(g, closeTo(128.0, 1.0));
      expect(b, closeTo(128.0, 1.0));
    });

    test('positive exposure brightens image', () {
      final source = _testImage(r: 100, g: 100, b: 100);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(exposure: 0.5)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r, greaterThan(100.0));
    });

    test('negative exposure darkens image', () {
      final source = _testImage(r: 200, g: 200, b: 200);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(exposure: -0.5)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r, lessThan(200.0));
    });

    test('brightness offset works', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipeUp = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(brightness: 0.5)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final up = EditTransformationEngine.apply(source, recipeUp);
      final (r1, _, _) = _avgColor(up.image);
      expect(r1, greaterThan(128.0));

      final recipeDown = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(brightness: -0.5)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final down = EditTransformationEngine.apply(source, recipeDown);
      final (r2, _, _) = _avgColor(down.image);
      expect(r2, lessThan(128.0));
    });

    test('saturation at -1.0 produces grayscale-like', () {
      // Use a strongly colored image
      final source = _testImage(r: 255, g: 0, b: 0);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(saturation: -1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      // All channels should be roughly equal (grayscale)
      expect((r - g).abs(), lessThan(2.0));
      expect((g - b).abs(), lessThan(2.0));
    });

    test('saturation at +1.0 boosts colors', () {
      final source = _testImage(r: 200, g: 100, b: 50);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(saturation: 1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, _, _) = _avgColor(result.image);
      // Red should be boosted
      expect(r, greaterThan(200.0));
    });

    test('temperature warm shifts red up, blue down', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(temperature: 1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r, greaterThan(b));
    });

    test('temperature cool shifts blue up, red down', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(temperature: -1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(b, greaterThan(r));
    });

    test('vignette darkens edges', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(vignette: -1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      // Center should be brighter than edges
      final (cr, cg, cb) = _centerPixel(result.image);
      // Edge pixel (0,0)
      final edgePx = result.image.getPixel(0, 0);
      expect(cr, greaterThan(edgePx.r.toDouble()));
    });

    test('tint green shifts green down', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(tint: 1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (_, g, _) = _avgColor(result.image);
      // Tint +1.0 = magenta (green down, red/blue up)
      expect(g, lessThan(128.0));
    });

    test('contrast positive expands range', () {
      final source = _gradientImage(width: 50, height: 50);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment(contrast: 1.0)],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      // Dark end should be darker, bright end brighter
      final darkPx = result.image.getPixel(0, 0);
      final brightPx = result.image.getPixel(49, 0);
      expect(brightPx.r.toDouble() - darkPx.r.toDouble(), greaterThan(150.0));
    });

    test('pipeline processes in correct order', () {
      // Exposure first, then brightness - verify both applied
      final source = _testImage(r: 100, g: 100, b: 100);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.adjustment(
            exposure: 0.3,
            brightness: 0.3,
          ),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, _, _) = _avgColor(result.image);
      // Both should contribute to brightening
      expect(r, greaterThan(120.0));
    });
  });

  // ==========================================================================
  // EditRecipe with geometric + adjustment combination
  // ==========================================================================
  group('Combined geometric + adjustment', () {
    test('rotate + adjustment both applied', () {
      final source = _testImage(r: 128, g: 128, b: 128);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.rotate(degrees: 90),
          EditOperation.adjustment(exposure: 0.5),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      // Image should be rotated (same dims for square image)
      expect(result.outputWidth, source.width);
      // And brightened
      final (r, _, _) = _avgColor(result.image);
      expect(r, greaterThan(128.0));
    });
  });

  // ==========================================================================
  // Edge cases
  // ==========================================================================
  group('Edge cases', () {
    test('empty recipe produces no-op', () {
      final source = _testImage();
      final recipe = EditRecipe(
        photoId: 'test',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      expect(result.outputWidth, source.width);
      expect(result.outputHeight, source.height);
    });

    test('very small image does not crash', () {
      final source = _testImage(width: 2, height: 2);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.adjustment(
            exposure: 1.0,
            saturation: -1.0,
            vignette: -1.0,
          ),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      expect(result.outputWidth, 2);
      expect(result.outputHeight, 2);
    });

    test('full-strength adjustments do not crash', () {
      final source = _testImage();
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [
          EditOperation.adjustment(
            exposure: 1.0,
            brightness: 1.0,
            contrast: 1.0,
            highlights: 1.0,
            shadows: 1.0,
            whites: 1.0,
            blacks: 1.0,
            saturation: 1.0,
            vibrance: 1.0,
            temperature: 1.0,
            tint: 1.0,
            sharpness: 1.0,
            clarity: 1.0,
            vignette: -1.0,
          ),
        ],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      // Should not throw
      final result = EditTransformationEngine.apply(source, recipe);
      expect(result.outputWidth, source.width);
    });

    test('no-op adjustments produce neutral result', () {
      final source = _testImage(r: 100, g: 150, b: 200);
      final recipe = EditRecipe(
        photoId: 'test',
        operations: [EditOperation.adjustment()],
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final result = EditTransformationEngine.apply(source, recipe);
      final (r, g, b) = _avgColor(result.image);
      expect(r, closeTo(100.0, 1.0));
      expect(g, closeTo(150.0, 1.0));
      expect(b, closeTo(200.0, 1.0));
    });
  });
}
