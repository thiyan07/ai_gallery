import 'dart:ui' as ui;

/// Frame/border configuration for the photo.
///
/// Frames are rendered as a border around the image. The width is relative
/// to the shorter dimension of the image (0.0 = no frame, 0.1 = 10% of
/// image width).
class FrameConfig {
  final double width; // 0.0–0.2, relative to image dimension
  final int color; // ARGB packed integer
  final double opacity; // 0.0–1.0
  final double cornerRadius; // 0.0–1.0, relative to width
  final bool roundedCorners; // Whether to round the image corners
  final double imageCornerRadius; // 0.0–0.1, relative to image size

  const FrameConfig({
    this.width = 0.0,
    this.color = 0xFFFFFFFF,
    this.opacity = 1.0,
    this.cornerRadius = 0.0,
    this.roundedCorners = false,
    this.imageCornerRadius = 0.0,
  });

  bool get isEmpty => width <= 0.0;
  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toMap() => {
        'width': width,
        'color': color,
        'opacity': opacity,
        'cornerRadius': cornerRadius,
        'roundedCorners': roundedCorners,
        'imageCornerRadius': imageCornerRadius,
      };

  factory FrameConfig.fromMap(Map<String, dynamic> map) => FrameConfig(
        width: (map['width'] as num?)?.toDouble() ?? 0.0,
        color: map['color'] as int? ?? 0xFFFFFFFF,
        opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
        cornerRadius: (map['cornerRadius'] as num?)?.toDouble() ?? 0.0,
        roundedCorners: map['roundedCorners'] as bool? ?? false,
        imageCornerRadius: (map['imageCornerRadius'] as num?)?.toDouble() ?? 0.0,
      );

  FrameConfig copyWith({
    double? width,
    int? color,
    double? opacity,
    double? cornerRadius,
    bool? roundedCorners,
    double? imageCornerRadius,
  }) {
    return FrameConfig(
      width: width ?? this.width,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      roundedCorners: roundedCorners ?? this.roundedCorners,
      imageCornerRadius: imageCornerRadius ?? this.imageCornerRadius,
    );
  }

  /// Get frame color as ui.Color.
  ui.Color get uiColor => ui.Color(
        ((opacity * 255).round() << 24) | (color & 0x00FFFFFF),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameConfig &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          color == other.color &&
          opacity == other.opacity &&
          cornerRadius == other.cornerRadius &&
          roundedCorners == other.roundedCorners &&
          imageCornerRadius == other.imageCornerRadius;

  @override
  int get hashCode => Object.hash(
        width,
        color,
        opacity,
        cornerRadius,
        roundedCorners,
        imageCornerRadius,
      );
}
