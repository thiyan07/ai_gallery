import 'dart:math';
import 'dart:typed_data';

import '../../../domain/models/edit/edit_mask.dart';
import '../../../domain/models/object_detection_model.dart';

/// Maximum mask dimensions to prevent excessive memory allocation.
const int _maxMaskDimension = 10000;
const int _maxMaskPixels = 100_000_000; // ~100 MP

/// Converts AI detection results into EditMask objects for selective editing.
///
/// Supports feathered masks from bounding boxes, multi-object union masks,
/// and class-based filtering (e.g., only "person" detections).
class ObjectMaskService {
  /// Generate a mask from a single detection's bounding box.
  ///
  /// [detection] — the detected object with bounding box in normalized coords.
  /// [imageWidth], [imageHeight] — dimensions of the target image.
  /// [feather] — edge softening radius in normalized units (0.0–0.1).
  /// [padding] — extra padding around the box in normalized units.
  static EditMask fromDetection(
    DetectedObject detection, {
    required int imageWidth,
    required int imageHeight,
    double feather = 0.02,
    double padding = 0.01,
  }) {
    assert(imageWidth > 0 && imageHeight > 0);
    if (imageWidth > _maxMaskDimension || imageHeight > _maxMaskDimension) {
      return EditMask.empty(
        min(imageWidth, _maxMaskDimension),
        min(imageHeight, _maxMaskDimension),
      );
    }
    final ltrb = detection.boundingBoxLTRB;
    final left = (ltrb[0] - padding).clamp(0.0, 1.0);
    final top = (ltrb[1] - padding).clamp(0.0, 1.0);
    final right = (ltrb[2] + padding).clamp(0.0, 1.0);
    final bottom = (ltrb[3] + padding).clamp(0.0, 1.0);

    return fromNormalizedBox(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      feather: feather,
    );
  }

  /// Generate a union mask from multiple detections.
  ///
  /// Optionally filter by label (e.g., only "person").
  /// Bounding boxes are rasterized into a single binary mask with feathered edges.
  static EditMask fromDetections(
    List<DetectedObject> detections, {
    required int imageWidth,
    required int imageHeight,
    String? labelFilter,
    double feather = 0.02,
    double padding = 0.01,
  }) {
    final filtered = labelFilter != null
        ? detections.where((d) => d.label == labelFilter).toList()
        : detections;

    if (filtered.isEmpty) {
      return EditMask.empty(imageWidth, imageHeight);
    }

    // Start with empty mask, union each detection
    final data = Uint8List(imageWidth * imageHeight);

    for (final det in filtered) {
      final ltrb = det.boundingBoxLTRB;
      final left = ((ltrb[0] - padding) * imageWidth).round().clamp(0, imageWidth - 1);
      final top = ((ltrb[1] - padding) * imageHeight).round().clamp(0, imageHeight - 1);
      final right = ((ltrb[2] + padding) * imageWidth).round().clamp(0, imageWidth - 1);
      final bottom = ((ltrb[3] + padding) * imageHeight).round().clamp(0, imageHeight - 1);

      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          data[y * imageWidth + x] = 255;
        }
      }
    }

    // Apply feather if requested
    if (feather > 0 && filtered.length == 1) {
      return _applyFeather(
        data,
        imageWidth,
        imageHeight,
        feather,
      );
    }

    return EditMask(
      width: imageWidth,
      height: imageHeight,
      data: data,
      feather: feather,
    );
  }

  /// Generate a mask from a normalized bounding box (left, top, right, bottom).
  static EditMask fromNormalizedBox({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required int imageWidth,
    required int imageHeight,
    double feather = 0.0,
  }) {
    final data = Uint8List(imageWidth * imageHeight);

    final x0 = (left * imageWidth).round().clamp(0, imageWidth - 1);
    final y0 = (top * imageHeight).round().clamp(0, imageHeight - 1);
    final x1 = (right * imageWidth).round().clamp(0, imageWidth - 1);
    final y1 = (bottom * imageHeight).round().clamp(0, imageHeight - 1);

    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        data[y * imageWidth + x] = 255;
      }
    }

    if (feather > 0) {
      return _applyFeather(data, imageWidth, imageHeight, feather);
    }

    return EditMask(
      width: imageWidth,
      height: imageHeight,
      data: data,
    );
  }

  /// Generate an inverted mask (background selection).
  static EditMask inverted(EditMask mask) {
    final inverted = Uint8List(mask.data.length);
    for (var i = 0; i < mask.data.length; i++) {
      inverted[i] = mask.data[i] == 0 ? 255 : 0;
    }
    return EditMask(
      width: mask.width,
      height: mask.height,
      data: inverted,
      feather: mask.feather,
      opacity: mask.opacity,
    );
  }

  /// Combine two masks with union (OR) operation.
  static EditMask union(EditMask a, EditMask b) {
    assert(a.width == b.width && a.height == b.height);
    final data = Uint8List(a.data.length);
    for (var i = 0; i < data.length; i++) {
      data[i] = max(a.data[i], b.data[i]);
    }
    return EditMask(
      width: a.width,
      height: a.height,
      data: data,
    );
  }

  /// Subtract mask b from mask a (AND NOT operation).
  static EditMask subtract(EditMask a, EditMask b) {
    assert(a.width == b.width && a.height == b.height);
    final data = Uint8List(a.data.length);
    for (var i = 0; i < data.length; i++) {
      data[i] = a.data[i] > 0 && b.data[i] == 0 ? 255 : 0;
    }
    return EditMask(
      width: a.width,
      height: a.height,
      data: data,
    );
  }

  /// Apply feathering (distance-based falloff at mask edges).
  static EditMask _applyFeather(
    Uint8List data,
    int width,
    int height,
    double feather,
  ) {
    final featherPixels = (feather * max(width, height)).round();
    if (featherPixels <= 0) {
      return EditMask(width: width, height: height, data: data);
    }

    final result = Uint8List(data.length);

    // Find edge pixels (selected adjacent to unselected)
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        if (data[idx] == 0) {
          // Check if near edge of selection
          var minDist = double.infinity;
          for (var dy = -featherPixels; dy <= featherPixels; dy++) {
            for (var dx = -featherPixels; dx <= featherPixels; dx++) {
              final ny = y + dy;
              final nx = x + dx;
              if (ny >= 0 &&
                  ny < height &&
                  nx >= 0 &&
                  nx < width &&
                  data[ny * width + nx] == 255) {
                final dist = sqrt(dx * dx + dy * dy);
                if (dist < minDist) minDist = dist;
              }
            }
          }
          if (minDist <= featherPixels) {
            final alpha =
                ((1.0 - minDist / featherPixels) * 255).round().clamp(0, 255);
            result[idx] = alpha;
          } else {
            result[idx] = 0;
          }
        } else {
          result[idx] = 255;
        }
      }
    }

    return EditMask(
      width: width,
      height: height,
      data: result,
      feather: feather,
    );
  }
}
