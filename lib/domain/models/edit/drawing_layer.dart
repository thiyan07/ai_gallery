import 'dart:ui' as ui;

/// A single drawing stroke composed of points.
///
/// Coordinates are normalized (0.0–1.0) in image-relative space:
/// x=0 left, x=1 right, y=0 top, y=1 bottom.
/// This ensures strokes remain correct after resize and on different screens.
class StrokePoint {
  /// Normalized x coordinate (0.0–1.0).
  final double x;

  /// Normalized y coordinate (0.0–1.0).
  final double y;

  /// Pressure for stylus input (0.0–1.0), defaults to 1.0 for touch.
  final double pressure;

  const StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
  });

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        if (pressure != 1.0) 'pressure': pressure,
      };

  factory StrokePoint.fromMap(Map<String, dynamic> map) => StrokePoint(
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        pressure: (map['pressure'] as num?)?.toDouble() ?? 1.0,
      );

  /// Interpolate between two points.
  static StrokePoint lerp(StrokePoint a, StrokePoint b, double t) {
    return StrokePoint(
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      pressure: a.pressure + (b.pressure - a.pressure) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokePoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          pressure == other.pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);
}

/// Brush type for drawing strokes.
enum BrushType {
  round,
  soft,
}

/// A single drawing stroke with properties.
class Stroke {
  final List<StrokePoint> points;
  final int color; // ARGB packed integer
  final double opacity; // 0.0–1.0
  final double width; // Normalized width relative to image (0.001–0.1)
  final BrushType brushType;

  const Stroke({
    required this.points,
    required this.color,
    this.opacity = 1.0,
    this.width = 0.01,
    this.brushType = BrushType.round,
  });

  bool get isEmpty => points.isEmpty;

  Map<String, dynamic> toMap() => {
        'points': points.map((p) => p.toMap()).toList(),
        'color': color,
        'opacity': opacity,
        'width': width,
        'brushType': brushType.name,
      };

  factory Stroke.fromMap(Map<String, dynamic> map) => Stroke(
        points: (map['points'] as List)
            .map((p) => StrokePoint.fromMap(p as Map<String, dynamic>))
            .toList(),
        color: map['color'] as int,
        opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
        width: (map['width'] as num?)?.toDouble() ?? 0.01,
        brushType: BrushType.values.firstWhere(
          (b) => b.name == map['brushType'],
          orElse: () => BrushType.round,
        ),
      );

  /// Get the color as a ui.Color.
  ui.Color get uiColor => ui.Color(color);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stroke &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          opacity == other.opacity &&
          width == other.width &&
          brushType == other.brushType &&
          _pointsEqual(points, other.points);

  @override
  int get hashCode => Object.hash(color, opacity, width, brushType, points.length);

  static bool _pointsEqual(List<StrokePoint> a, List<StrokePoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Drawing layer containing all strokes for a photo.
///
/// Stored as a single operation in the edit recipe.
/// Uses normalized coordinates for resolution independence.
class DrawingLayer {
  final List<Stroke> strokes;

  const DrawingLayer({this.strokes = const []});

  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;

  int get strokeCount => strokes.length;

  Map<String, dynamic> toMap() => {
        'strokes': strokes.map((s) => s.toMap()).toList(),
      };

  factory DrawingLayer.fromMap(Map<String, dynamic> map) => DrawingLayer(
        strokes: (map['strokes'] as List?)
                ?.map((s) => Stroke.fromMap(s as Map<String, dynamic>))
                .toList() ??
            [],
      );

  /// Create a copy with an additional stroke.
  DrawingLayer addStroke(Stroke stroke) {
    return DrawingLayer(strokes: [...strokes, stroke]);
  }

  /// Create a copy without the last stroke (undo).
  DrawingLayer removeLastStroke() {
    if (strokes.isEmpty) return this;
    return DrawingLayer(strokes: strokes.sublist(0, strokes.length - 1));
  }

  /// Create a copy with all strokes removed.
  DrawingLayer clear() => const DrawingLayer();
}
