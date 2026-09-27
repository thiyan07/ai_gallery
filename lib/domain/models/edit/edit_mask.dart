import 'dart:typed_data';

/// A binary mask representing a region of interest in an image.
///
/// Coordinates are in normalized image space (0.0–1.0) to remain
/// resolution-independent. The mask can represent:
/// - Object selection for removal
/// - Foreground/background segmentation
/// - Brush strokes for manual selection
/// - AI-generated segmentation results
class EditMask {
  /// Width of the mask in pixels.
  final int width;

  /// Height of the mask in pixels.
  final int height;

  /// Raw mask data as bytes (0 = unselected, 255 = fully selected).
  /// Row-major order, one byte per pixel.
  final Uint8List data;

  /// Feather radius in normalized units (0.0–0.1).
  /// Softens the mask edges for compositing.
  final double feather;

  /// Overall mask opacity (0.0–1.0).
  final double opacity;

  const EditMask({
    required this.width,
    required this.height,
    required this.data,
    this.feather = 0.0,
    this.opacity = 1.0,
  });

  /// Create an empty mask of given dimensions.
  factory EditMask.empty(int width, int height) {
    return EditMask(
      width: width,
      height: height,
      data: Uint8List(width * height),
    );
  }

  /// Create a fully opaque (all-selected) mask.
  factory EditMask.full(int width, int height) {
    return EditMask(
      width: width,
      height: height,
      data: Uint8List(width * height)..fillRange(0, width * height, 255),
    );
  }

  /// Total number of pixels.
  int get pixelCount => width * height;

  /// Number of selected pixels (> 0).
  int get selectedPixels {
    var count = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] > 0) count++;
    }
    return count;
  }

  /// Fraction of the mask that is selected (0.0–1.0).
  double get fillRatio => pixelCount > 0 ? selectedPixels / pixelCount : 0.0;

  /// Whether the mask has any selected pixels.
  bool get isEmpty => selectedPixels == 0;

  /// Whether the mask has any unselected pixels.
  bool get isFull => selectedPixels == pixelCount;

  /// Get mask value at (x, y) in pixel coordinates.
  int getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 0;
    return data[y * width + x];
  }

  /// Set mask value at (x, y) in pixel coordinates.
  void setPixel(int x, int y, int value) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    data[y * width + x] = value.clamp(0, 255);
  }

  /// Get mask value at normalized coordinates (0.0–1.0).
  double getNormalized(double nx, double ny) {
    final x = (nx * (width - 1)).round().clamp(0, width - 1);
    final y = (ny * (height - 1)).round().clamp(0, height - 1);
    return data[y * width + x] / 255.0;
  }

  /// Paint a filled circle at normalized coordinates.
  void paintCircle(double nx, double ny, double normalizedRadius, int value) {
    final cx = (nx * (width - 1)).round();
    final cy = (ny * (height - 1)).round();
    final r = (normalizedRadius * width).round();
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy <= r * r) {
          final px = cx + dx;
          final py = cy + dy;
          if (px >= 0 && px < width && py >= 0 && py < height) {
            data[py * width + px] = value.clamp(0, 255);
          }
        }
      }
    }
  }

  /// Paint a feathered circle at normalized coordinates.
  void paintSoftCircle(
      double nx, double ny, double normalizedRadius, int value) {
    final cx = (nx * (width - 1)).round();
    final cy = (ny * (height - 1)).round();
    final r = (normalizedRadius * width).round();
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final dist = (dx * dx + dy * dy).toDouble();
        final r2 = (r * r).toDouble();
        if (dist <= r2) {
          // Smooth falloff: 1 at center, 0 at edge
          final alpha = (1.0 - dist / r2) * value;
          final px = cx + dx;
          final py = cy + dy;
          if (px >= 0 && px < width && py >= 0 && py < height) {
            final idx = py * width + px;
            // Max compositing
            final newVal = data[idx] > alpha.round()
                ? data[idx]
                : alpha.round().clamp(0, 255);
            data[idx] = newVal;
          }
        }
      }
    }
  }

  /// Clear the mask entirely.
  void clear() {
    data.fillRange(0, data.length, 0);
  }

  /// Fill the mask entirely.
  void fillAll() {
    data.fillRange(0, data.length, 255);
  }

  /// Invert the mask.
  void invert() {
    for (var i = 0; i < data.length; i++) {
      data[i] = 255 - data[i];
    }
  }

  /// Apply feathering (Gaussian-like blur on mask edges).
  void applyFeather(double normalizedRadius) {
    if (normalizedRadius <= 0) return;
    final radius = (normalizedRadius * width).round().clamp(1, 20);
    // Simple box blur for feathering
    final temp = Uint8List.fromList(data);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var sum = 0;
        var count = 0;
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final px = x + dx;
            final py = y + dy;
            if (px >= 0 && px < width && py >= 0 && py < height) {
              sum += temp[py * width + px];
              count++;
            }
          }
        }
        data[y * width + x] = (sum / count).round().clamp(0, 255);
      }
    }
  }

  /// Create a new mask from this one with a different resolution.
  EditMask resize(int newWidth, int newHeight) {
    final newMask = EditMask.empty(newWidth, newHeight);
    for (var ny = 0; ny < newHeight; ny++) {
      for (var nx = 0; nx < newWidth; nx++) {
        final srcX = (nx * width / newWidth).round().clamp(0, width - 1);
        final srcY = (ny * height / newHeight).round().clamp(0, height - 1);
        newMask.data[ny * newWidth + nx] = data[srcY * width + srcX];
      }
    }
    return newMask;
  }

  /// Serialize to a map for storage.
  Map<String, dynamic> toMap() => {
        'width': width,
        'height': height,
        'data': data.toList(),
        'feather': feather,
        'opacity': opacity,
      };

  /// Deserialize from a map.
  factory EditMask.fromMap(Map<String, dynamic> map) => EditMask(
        width: map['width'] as int,
        height: map['height'] as int,
        data: Uint8List.fromList((map['data'] as List).cast<int>()),
        feather: (map['feather'] as num?)?.toDouble() ?? 0.0,
        opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
      );

  /// Serialize to a compact map (data as base64 string for DB storage).
  Map<String, dynamic> toCompactMap() => {
        'w': width,
        'h': height,
        'd': data, // stored as BLOB in SQLite
        'f': feather,
        'o': opacity,
      };

  /// Deserialize from a compact map.
  factory EditMask.fromCompactMap(Map<String, dynamic> map) => EditMask(
        width: map['w'] as int,
        height: map['h'] as int,
        data: map['d'] is Uint8List
            ? map['d'] as Uint8List
            : Uint8List.fromList((map['d'] as List).cast<int>()),
        feather: (map['f'] as num?)?.toDouble() ?? 0.0,
        opacity: (map['o'] as num?)?.toDouble() ?? 1.0,
      );
}
