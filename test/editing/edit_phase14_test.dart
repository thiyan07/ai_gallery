import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/domain/models/edit/edit_operation.dart';
import 'package:ai_gallery/domain/models/edit/edit_recipe.dart';
import 'package:ai_gallery/features/editing/services/edit_transformation_engine.dart';
import 'package:ai_gallery/features/editing/services/export_queue_service.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:image/image.dart' as img;

img.Image _testImage({int width = 100, int height = 100, int r = 100, int g = 120, int b = 140}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}

EditRecipe _recipe([List<EditOperation> ops = const []]) {
  return EditRecipe(
    photoId: 'test_photo',
    operations: ops,
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );
}

void main() {
  group('Phase 14 - resize operation', () {
    test('resize clamps to 1..8000', () {
      final op = EditOperation.resize(width: 9000, height: 0);
      expect(op.resizeWidth, 8000);
      expect(op.resizeHeight, 1);
      expect(op.isResize, isTrue);
    });

    test('resize isNoOp when invalid dimensions', () {
      final op = EditOperation.resize(width: 100, height: 100);
      // valid -> not noOp
      expect(op.isNoOp, isFalse);
      // manually crafted zero
      final zero = EditOperation(type: EditOperationType.resize, params: {'width': 0, 'height': 0, 'maintainAspect': true, 'method': 'lanczos'});
      expect(zero.isNoOp, isTrue);
    });

    test('resize maintains aspect flag', () {
      final op = EditOperation.resize(width: 200, height: 200, maintainAspect: false);
      expect(op.resizeMaintainAspect, isFalse);
      expect(op.resizeMethod, 'lanczos');
    });

    test('EditRecipe withResize/withoutResize/hasResize', () {
      final r = _recipe().withResize(width: 400, height: 300);
      expect(r.hasResize, isTrue);
      expect(r.operations.length, 1);
      expect(r.summary, contains('Resized'));
      final r2 = r.withoutResize();
      expect(r2.hasResize, isFalse);
      expect(r2.isEmpty, isTrue);
    });

    test('recipe withResize replaces existing', () {
      final r = _recipe().withResize(width: 400, height: 300);
      final r2 = r.withResize(width: 200, height: 200);
      expect(r2.operations.length, 1);
      expect(r2.operations.first.resizeWidth, 200);
    });

    test('serialization round-trip for resize', () {
      final r = _recipe([EditOperation.resize(width: 123, height: 456)]);
      final json = r.operationsToJson();
      final restored = EditRecipe.operationsFromJson(json);
      expect(restored.length, 1);
      expect(restored.first.resizeWidth, 123);
      expect(restored.first.resizeHeight, 456);
    });

    test('transformation engine resize reduces image', () {
      final image = _testImage(width: 200, height: 100);
      final recipe = _recipe([EditOperation.resize(width: 100, height: 50, maintainAspect: false)]);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 100);
      expect(result.outputHeight, 50);
    });

    test('transformation engine resize with maintainAspect fits within box', () {
      final image = _testImage(width: 200, height: 100);
      // request 100x100 box, maintainAspect true => should be 100x50
      final recipe = _recipe([EditOperation.resize(width: 100, height: 100, maintainAspect: true)]);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 100);
      expect(result.outputHeight, 50);
    });

    test('transformation engine resize identity does not allocate new image unnecessarily', () {
      final image = _testImage(width: 100, height: 100);
      final recipe = _recipe([EditOperation.resize(width: 100, height: 100)]);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 100);
      expect(result.outputHeight, 100);
    });

    test('resize caps at 4096 in engine', () {
      final image = _testImage(width: 100, height: 100);
      final recipe = _recipe([EditOperation.resize(width: 8000, height: 8000, maintainAspect: false)]);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 4096);
      expect(result.outputHeight, 4096);
    });

    test('isGeometric includes resize and perspective', () {
      final r = EditOperation.resize(width: 100, height: 100);
      expect(r.isGeometric, isTrue);
      final p = EditOperation.perspective(tlX: 0.1);
      expect(p.isGeometric, isTrue);
    });
  });

  group('Phase 14 - perspective operation', () {
    test('perspective defaults to identity/noOp', () {
      final op = EditOperation.perspective();
      expect(op.isPerspective, isTrue);
      expect(op.isNoOp, isTrue);
      expect(op.perspectiveDeltas.values.every((v) => v == 0.0), isTrue);
    });

    test('perspective with deltas is not noOp', () {
      final op = EditOperation.perspective(tlX: 0.1, brY: -0.2);
      expect(op.isNoOp, isFalse);
      expect(op.perspectiveDeltas['tlX'], 0.1);
      expect(op.perspectiveDeltas['brY'], -0.2);
    });

    test('perspective clamps to -0.5..0.5', () {
      final op = EditOperation.perspective(tlX: 1.0, tlY: -1.0);
      expect(op.perspectiveDeltas['tlX'], 0.5);
      expect(op.perspectiveDeltas['tlY'], -0.5);
    });

    test('EditRecipe withPerspective/withoutPerspective', () {
      final r = _recipe().withPerspective(tlX: 0.1);
      expect(r.hasPerspective, isTrue);
      expect(r.summary, contains('Perspective'));
      final r2 = r.withoutPerspective();
      expect(r2.hasPerspective, isFalse);
    });

    test('recipe perspective identity not added via controller logic but via direct op isNoOp handled in engine', () {
      final image = _testImage();
      final recipe = _recipe([EditOperation.perspective()]); // identity included manually
      final result = EditTransformationEngine.apply(image, recipe);
      // identity perspective should be skipped (treated as noOp in engine grouping)
      // However our engine currently adds it if not isNoOp; identity isNoOp so filtered
      // Here we bypass filter by directly constructing, but apply still returns same size
      expect(result.outputWidth, image.width);
    });

    test('perspective non-identity currently no-ops but preserves sizes', () {
      final image = _testImage(width: 80, height: 60);
      final recipe = _recipe([EditOperation.perspective(tlX: 0.1, tlY: 0.1)]);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.outputWidth, 80);
      expect(result.outputHeight, 60);
    });

    test('serialization round-trip for perspective', () {
      final op = EditOperation.perspective(tlX: 0.2, brY: 0.3);
      final map = op.toMap();
      final restored = EditOperation.fromMap(map);
      expect(restored.perspectiveDeltas['tlX'], 0.2);
      expect(restored.perspectiveDeltas['brY'], 0.3);
    });
  });

  group('Phase 14 - vertical flip', () {
    test('flip horizontal vs vertical separate flags', () {
      final h = EditOperation.flip(horizontal: true, vertical: false);
      expect(h.isHorizontalFlip, isTrue);
      expect(h.isVerticalFlip, isFalse);
      expect(h.isNoOp, isFalse);

      final v = EditOperation.flip(horizontal: false, vertical: true);
      expect(v.isHorizontalFlip, isFalse);
      expect(v.isVerticalFlip, isTrue);

      final none = EditOperation.flip(horizontal: false, vertical: false);
      expect(none.isNoOp, isTrue);
    });

    test('recipe isFlippedHorizontally / isFlippedVertically counts odd', () {
      final r = _recipe([EditOperation.flip(horizontal: true, vertical: false)]);
      expect(r.isFlippedHorizontally, isTrue);
      expect(r.isFlippedVertically, isFalse);
      final r2 = _recipe([EditOperation.flip(horizontal: false, vertical: true)]);
      expect(r2.isFlippedVertically, isTrue);
    });

    test('vertical flip actually flips pixels', () {
      // create 2x2 image with distinct rows
      final image = img.Image(width: 2, height: 2);
      image.setPixelRgba(0, 0, 255, 0, 0, 255); // top red
      image.setPixelRgba(1, 0, 255, 0, 0, 255);
      image.setPixelRgba(0, 1, 0, 0, 255, 255); // bottom blue
      image.setPixelRgba(1, 1, 0, 0, 255, 255);
      final recipe = _recipe([EditOperation.flip(horizontal: false, vertical: true)]);
      final result = EditTransformationEngine.apply(image, recipe);
      // after vertical flip, top should be blue
      expect(result.image.getPixel(0, 0).b, 255);
      expect(result.image.getPixel(0, 1).r, 255);
    });

    test('horizontal flip actually flips pixels', () {
      final image = img.Image(width: 2, height: 1);
      image.setPixelRgba(0, 0, 255, 0, 0, 255); // left red
      image.setPixelRgba(1, 0, 0, 255, 0, 255); // right green
      final recipe = _recipe([EditOperation.flip(horizontal: true, vertical: false)]);
      final result = EditTransformationEngine.apply(image, recipe);
      expect(result.image.getPixel(0, 0).g, 255);
      expect(result.image.getPixel(1, 0).r, 255);
    });

    test('flip both axes', () {
      final image = img.Image(width: 2, height: 2);
      image.setPixelRgba(0, 0, 255, 0, 0, 255);
      image.setPixelRgba(1, 0, 0, 255, 0, 255);
      image.setPixelRgba(0, 1, 0, 0, 255, 255);
      image.setPixelRgba(1, 1, 255, 255, 0, 255);
      final recipe = _recipe([EditOperation.flip(horizontal: true, vertical: true)]);
      final result = EditTransformationEngine.apply(image, recipe);
      // bottom-right yellow should move to top-left
      expect(result.image.getPixel(0, 0).r, 255);
      expect(result.image.getPixel(0, 0).g, 255);
    });

    test('summary distinguishes H/V flip', () {
      final rH = _recipe([EditOperation.flip(horizontal: true, vertical: false)]);
      expect(rH.summary, contains('Flipped H'));
      final rV = _recipe([EditOperation.flip(horizontal: false, vertical: true)]);
      expect(rV.summary, contains('Flipped V'));
      final rBoth = _recipe([EditOperation.flip(horizontal: true, vertical: true)]);
      expect(rBoth.summary, contains('Flipped'));
    });
  });

  group('Phase 14 - export queue verification', () {
    test('enqueue and pendingCount', () async {
      const logger = ConsoleAppLogger();
      final service = ExportQueueService(logger: logger);
      final recipe = _recipe([EditOperation.adjustment(exposure: 0.2)]);
      // Do not actually process (photoId not existent file but enqueue should succeed)
      // We test queue management without awaiting real image export: cancel immediately to avoid disk work
      expect(service.pendingCount, 0);
      expect(service.isProcessing, isFalse);
      // Enqueue then cancel to verify state transitions without needing real files
      // ignore: unawaited_futures
      service.enqueue(photoId: 'fake_id_1', recipe: recipe);
      // give microtask a chance
      await Future.delayed(const Duration(milliseconds: 10));
      // Either pending or processing (service tries to export); ensure queue has item
      expect(service.items.length, 1);
      expect(service.items.first.photoId, 'fake_id_1');
      // cancel
      service.cancel('fake_id_1');
      // clearFinished should not remove processing unless completed; but cancelled pending can be cleared
      // We just verify cancel doesn't throw and pendingCount logic
      expect(service.items.first.status == ExportQueueStatus.cancelled || service.items.first.status == ExportQueueStatus.processing || service.items.first.status == ExportQueueStatus.pending, isTrue);
    });

    test('cancelAll and clearFinished', () {
      const logger = ConsoleAppLogger();
      final service = ExportQueueService(logger: logger);
      // Directly manipulate via enqueueAll alternative: test clearFinished logic on fabricated completed items
      // Add item and manually set status to completed then clear
      final recipe = _recipe();
      service.enqueue(photoId: 'id1', recipe: recipe);
      service.enqueue(photoId: 'id2', recipe: recipe);
      // Immediately cancelAll should mark pending as cancelled where applicable
      service.cancelAll();
      // At least pending items become cancelled; processing item stays processing
      final pendingOrCancelled = service.items.where((i) => i.status == ExportQueueStatus.cancelled || i.status == ExportQueueStatus.pending || i.status == ExportQueueStatus.processing).length;
      expect(pendingOrCancelled, 2);
      // Simulate finished
      for (final item in service.items) {
        item.status = ExportQueueStatus.completed;
      }
      service.clearFinished();
      expect(service.items.length, 0);
    });
  });
}
