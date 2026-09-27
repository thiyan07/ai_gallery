import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/editing/services/edit_plan_service.dart';
import 'package:ai_gallery/features/editing/services/edit_plan.dart';
import 'package:ai_gallery/domain/models/edit/edit_operation.dart';
import 'package:ai_gallery/domain/models/edit/edit_history.dart';
import 'package:ai_gallery/domain/models/edit/edit_recipe.dart';
import 'package:ai_gallery/domain/models/edit/edit_mask.dart';
import 'package:ai_gallery/domain/models/object_detection_model.dart';
import 'package:ai_gallery/features/editing/services/object_mask_service.dart';
import 'package:ai_gallery/features/editing/services/edit_document_versioning.dart';
import 'package:ai_gallery/features/editing/services/edit_clipboard.dart';
import 'package:ai_gallery/features/editing/services/edit_transformation_engine.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';

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

/// Helper to create a test recipe.
EditRecipe _recipe([List<EditOperation> ops = const []]) {
  return EditRecipe(
    photoId: 'test_photo',
    operations: ops,
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );
}

const _logger = ConsoleAppLogger();

void main() {
  // =========================================================================
  // EDIT PLAN SERVICE
  // =========================================================================
  group('EditPlanService', () {
    late EditPlanService service;

    setUp(() {
      service = EditPlanService(logger: _logger);
    });

    test('generates plan for "make it brighter"', () {
      final plan = service.analyzePrompt('make it brighter');
      expect(plan.steps.length, 1);
      expect(plan.steps.first.description, 'Increase brightness');
      expect(plan.steps.first.operation.type, EditOperationType.adjustment);
      expect(plan.steps.first.operation.exposure, greaterThan(0));
    });

    test('generates plan for "warmer and more vibrant"', () {
      final plan = service.analyzePrompt('warmer and more vibrant');
      expect(plan.steps.length, 2);
      final descriptions = plan.steps.map((s) => s.description).toList();
      expect(descriptions, contains('Warm up color temperature'));
      expect(descriptions, contains('Increase saturation'));
    });

    test('generates multi-step plan for HDR', () {
      final plan = service.analyzePrompt('make it HDR');
      expect(plan.steps.length, 4);
      expect(plan.overallConfidence, greaterThan(0));
    });

    test('generates cinematic preset plan', () {
      final plan = service.analyzePrompt('cinematic film look');
      expect(plan.steps.length, 3);
      final descriptions = plan.steps.map((s) => s.description).toList();
      expect(descriptions, contains('Slightly increase contrast'));
    });

    test('generates noir plan', () {
      final plan = service.analyzePrompt('noir dark moody');
      expect(plan.steps.length, 3);
      final satValues = plan.steps
          .where((s) => s.operation.type == EditOperationType.adjustment)
          .map((s) => s.operation.saturation)
          .toList();
      expect(satValues, contains(-1.0));
    });

    test('returns empty plan for unmatched prompt', () {
      final plan = service.analyzePrompt('xyzzy foobar');
      expect(plan.steps, isEmpty);
      expect(plan.overallConfidence, 0.0);
    });

    test('plan serialization roundtrip', () {
      final plan = service.analyzePrompt('make it warmer');
      final json = plan.toJson();
      final restored = EditPlan.fromJson(json);
      expect(restored.planId, plan.planId);
      expect(restored.steps.length, plan.steps.length);
      expect(restored.prompt, plan.prompt);
    });
  });

  // =========================================================================
  // OBJECT MASK SERVICE
  // =========================================================================
  group('ObjectMaskService', () {
    test('creates mask from single detection', () {
      final det = DetectedObject(
        label: 'person',
        confidence: 0.9,
        boundingBox: [0.5, 0.5, 0.4, 0.6],
      );
      final mask = ObjectMaskService.fromDetection(
        det,
        imageWidth: 100,
        imageHeight: 100,
      );
      expect(mask.width, 100);
      expect(mask.height, 100);
      expect(mask.selectedPixels, greaterThan(0));
    });

    test('creates union mask from multiple detections', () {
      final dets = [
        DetectedObject(
          label: 'person',
          confidence: 0.9,
          boundingBox: [0.2, 0.5, 0.2, 0.6],
        ),
        DetectedObject(
          label: 'car',
          confidence: 0.8,
          boundingBox: [0.8, 0.5, 0.2, 0.3],
        ),
      ];
      final mask = ObjectMaskService.fromDetections(
        dets,
        imageWidth: 100,
        imageHeight: 100,
      );
      expect(mask.selectedPixels, greaterThan(0));
    });

    test('filters by label', () {
      final dets = [
        DetectedObject(
          label: 'person',
          confidence: 0.9,
          boundingBox: [0.5, 0.5, 0.2, 0.6],
        ),
        DetectedObject(
          label: 'car',
          confidence: 0.8,
          boundingBox: [0.5, 0.5, 0.2, 0.3],
        ),
      ];
      final personMask = ObjectMaskService.fromDetections(
        dets,
        imageWidth: 100,
        imageHeight: 100,
        labelFilter: 'person',
      );
      final carMask = ObjectMaskService.fromDetections(
        dets,
        imageWidth: 100,
        imageHeight: 100,
        labelFilter: 'car',
      );
      expect(
        personMask.selectedPixels,
        isNot(equals(carMask.selectedPixels)),
      );
    });

    test('inverts mask', () {
      final det = DetectedObject(
        label: 'face',
        confidence: 0.95,
        boundingBox: [0.5, 0.5, 0.3, 0.3],
      );
      final mask = ObjectMaskService.fromDetection(
        det,
        imageWidth: 100,
        imageHeight: 100,
        feather: 0.0,
      );
      final inv = ObjectMaskService.inverted(mask);
      expect(inv.selectedPixels, greaterThan(0));
      expect(inv.selectedPixels + mask.selectedPixels, equals(10000));
    });

    test('union of two masks', () {
      final a = EditMask.empty(50, 50);
      final b = EditMask.full(50, 50);
      final result = ObjectMaskService.union(a, b);
      expect(result.selectedPixels, 2500);
    });

    test('subtract masks', () {
      final a = EditMask.full(50, 50);
      final b = ObjectMaskService.fromNormalizedBox(
        left: 0.0,
        top: 0.0,
        right: 0.5,
        bottom: 0.5,
        imageWidth: 50,
        imageHeight: 50,
      );
      final result = ObjectMaskService.subtract(a, b);
      expect(result.selectedPixels, greaterThan(0));
      expect(result.selectedPixels, lessThan(2500));
    });

    test('empty mask when no detections match filter', () {
      final dets = [
        DetectedObject(
          label: 'car',
          confidence: 0.8,
          boundingBox: [0.5, 0.5, 0.2, 0.3],
        ),
      ];
      final mask = ObjectMaskService.fromDetections(
        dets,
        imageWidth: 100,
        imageHeight: 100,
        labelFilter: 'person',
      );
      expect(mask.selectedPixels, 0);
    });
  });

  // =========================================================================
  // EDIT HISTORY GROUPED OPERATIONS
  // =========================================================================
  group('EditHistory grouped operations', () {
    test('pushGroup creates a single undo entry', () {
      final history = EditHistoryManager();
      final ops1 = [
        EditOperation.adjustment(exposure: 0.2),
        EditOperation.adjustment(contrast: 0.3),
      ];
      history.pushState(ops1);

      final groupOps = [
        EditOperation.adjustment(saturation: 0.5),
        EditOperation.adjustment(sharpness: 0.3),
      ];
      history.pushGroup(groupOps, label: 'HDR adjustments');

      expect(history.canUndo, isTrue);
      history.undo();
      expect(history.currentOperations, equals(ops1));
    });

    test('undoLabel returns label of top snapshot', () {
      final history = EditHistoryManager();
      history.pushState([EditOperation.adjustment(exposure: 0.2)]);
      history.pushGroup(
        [EditOperation.adjustment(contrast: 0.5)],
        label: 'Increase contrast',
      );
      expect(history.undoLabel, 'Increase contrast');
    });
  });

  // =========================================================================
  // EDIT DOCUMENT VERSIONING
  // =========================================================================
  group('EditDocumentVersioning', () {
    late EditDocumentVersioning versioning;

    setUp(() {
      versioning = EditDocumentVersioning(logger: _logger);
    });

    test('saves and retrieves versions', () {
      final recipe = _recipe([
        EditOperation.adjustment(exposure: 0.2),
      ]);
      versioning.saveVersion('photo1', recipe, label: 'Initial');

      final versions = versioning.getVersions('photo1');
      expect(versions.length, 1);
      expect(versions.first.label, 'Initial');
    });

    test('enforces max version limit', () {
      final recipe = _recipe();
      for (var i = 0; i < 25; i++) {
        versioning.saveVersion('photo1', recipe);
      }
      final versions = versioning.getVersions('photo1');
      expect(versions.length, 20);
    });

    test('restores version and creates new entry', () {
      final v1 = versioning.saveVersion(
        'photo1',
        _recipe([EditOperation.adjustment(exposure: 0.2)]),
      );
      versioning.saveVersion(
        'photo1',
        _recipe([EditOperation.adjustment(contrast: 0.3)]),
      );

      final restored = versioning.restoreVersion(
        'photo1',
        v1.versionId,
      );
      expect(restored, isNotNull);
      expect(restored!.operations.length, 1);

      final versions = versioning.getVersions('photo1');
      expect(versions.length, 3);
      expect(versions.last.label, contains('Restored'));
    });

    test('compares versions', () {
      final v1 = versioning.saveVersion(
        'photo1',
        _recipe([EditOperation.adjustment(exposure: 0.2)]),
        label: 'Bright',
      );
      final v2 = versioning.saveVersion(
        'photo1',
        _recipe([
          EditOperation.adjustment(exposure: 0.2),
          EditOperation.adjustment(contrast: 0.3),
        ]),
        label: 'Bright + Contrast',
      );

      final diff = versioning.compareVersions(
        'photo1',
        v1.versionId,
        v2.versionId,
      );
      expect(diff['a_label'], 'Bright');
      expect(diff['b_label'], 'Bright + Contrast');
      expect(diff['a_operations'], 1);
      expect(diff['b_operations'], 2);
    });

    test('serialization roundtrip', () {
      versioning.saveVersion(
        'photo1',
        _recipe([EditOperation.adjustment(exposure: 0.2)]),
      );
      final json = versioning.toJson('photo1');
      versioning.clearVersions('photo1');
      expect(versioning.getVersions('photo1'), isEmpty);

      versioning.fromJson('photo1', json);
      expect(versioning.getVersions('photo1').length, 1);
    });
  });

  // =========================================================================
  // EDIT CLIPBOARD
  // =========================================================================
  group('EditClipboard', () {
    late EditClipboard clipboard;

    setUp(() {
      clipboard = EditClipboard.instance;
      clipboard.clear();
    });

    test('copyFrom stores operations', () {
      final recipe = _recipe([
        EditOperation.adjustment(exposure: 0.3),
        EditOperation.adjustment(contrast: -0.2),
      ]);
      clipboard.copyFrom('photo1', recipe);
      expect(clipboard.hasContent, isTrue);
    });

    test('pasteInto applies copied operations to new recipe', () {
      final source = _recipe([
        EditOperation.adjustment(exposure: 0.3),
        EditOperation.filter(presetId: 'vintage'),
      ]);
      clipboard.copyFrom('photo1', source);

      final target = _recipe();
      final result = clipboard.pasteInto(target);
      expect(result, isNotNull);
      expect(result!.operations.length, 2);
    });

    test('clear removes clipboard data', () {
      clipboard.copyFrom(
        'photo1',
        _recipe([EditOperation.adjustment(exposure: 0.5)]),
      );
      expect(clipboard.hasContent, isTrue);
      clipboard.clear();
      expect(clipboard.hasContent, isFalse);
    });

    test('copyTypesFrom filters operation types', () {
      final recipe = _recipe([
        EditOperation.adjustment(exposure: 0.3),
        EditOperation.filter(presetId: 'vintage'),
      ]);
      clipboard.copyTypesFrom('photo1', recipe,
          types: [EditOperationType.adjustment]);

      final target = _recipe();
      final result = clipboard.pasteInto(target);
      expect(result, isNotNull);
      expect(result!.operations.length, 1);
      expect(result.operations.first.type, EditOperationType.adjustment);
    });
  });

  // =========================================================================
  // CURVES & HSL RENDERING (Phase 29 additions to transformation engine)
  // =========================================================================
  group('EditTransformationEngine - Phase 29 operations', () {
    test('applies curves adjustment to image', () {
      final image = _testImage(r: 100, g: 100, b: 100);
      final recipe = _recipe([
        EditOperation.curves(
          rgbPoints: [
            {'x': 0.0, 'y': 0.0},
            {'x': 0.5, 'y': 0.7},
            {'x': 1.0, 'y': 1.0},
          ],
          intensity: 1.0,
        ),
      ]);

      final result = EditTransformationEngine.apply(image, recipe);
      final px = result.image.getPixel(50, 50);
      expect(px.r.toInt(), greaterThan(100));
    });

    test('applies HSL hue rotation', () {
      final image = _testImage(r: 255, g: 0, b: 0);
      final recipe = _recipe([
        EditOperation.hsl(
          channels: {
            'red': {'hue': 0.5, 'saturation': 0.0, 'luminance': 0.0},
          },
        ),
      ]);

      final result = EditTransformationEngine.apply(image, recipe);
      final px = result.image.getPixel(50, 50);
      // Hue rotation should change the color
      expect(px.r.toInt() != 255 || px.g.toInt() != 0, isTrue);
    });
  });
}
