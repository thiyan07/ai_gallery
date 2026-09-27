import 'dart:ui' as ui;

/// Text alignment options.
enum TextAlignment { left, center, right }

/// A single text layer that can be placed on the image.
///
/// Coordinates are normalized (0.0–1.0) in image-relative space.
/// This ensures text remains correctly positioned after resize and export.
class TextLayer {
  final String text;
  final double x; // Normalized x (0.0–1.0)
  final double y; // Normalized y (0.0–1.0)
  final double scale; // 0.1–5.0, default 1.0
  final double rotation; // Degrees, -180 to 180
  final int color; // ARGB packed integer
  final double opacity; // 0.0–1.0
  final String fontFamily; // Font family name
  final double fontSize; // Base size relative to image (0.01–0.2)
  final TextAlignment alignment;
  final bool hasBackground;
  final int backgroundColor; // ARGB packed integer
  final double backgroundOpacity; // 0.0–1.0
  final double backgroundPadding; // Relative to text size (0.0–0.5)
  final double backgroundCornerRadius; // Relative to padding (0.0–1.0)

  const TextLayer({
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.color = 0xFFFFFFFF,
    this.opacity = 1.0,
    this.fontFamily = 'Roboto',
    this.fontSize = 0.05,
    this.alignment = TextAlignment.center,
    this.hasBackground = false,
    this.backgroundColor = 0xFF000000,
    this.backgroundOpacity = 0.6,
    this.backgroundPadding = 0.1,
    this.backgroundCornerRadius = 0.15,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'color': color,
        'opacity': opacity,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'alignment': alignment.name,
        'hasBackground': hasBackground,
        'backgroundColor': backgroundColor,
        'backgroundOpacity': backgroundOpacity,
        'backgroundPadding': backgroundPadding,
        'backgroundCornerRadius': backgroundCornerRadius,
      };

  factory TextLayer.fromMap(Map<String, dynamic> map) => TextLayer(
        text: map['text'] as String,
        x: (map['x'] as num?)?.toDouble() ?? 0.5,
        y: (map['y'] as num?)?.toDouble() ?? 0.5,
        scale: (map['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
        color: map['color'] as int? ?? 0xFFFFFFFF,
        opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
        fontFamily: map['fontFamily'] as String? ?? 'Roboto',
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 0.05,
        alignment: TextAlignment.values.firstWhere(
          (a) => a.name == map['alignment'],
          orElse: () => TextAlignment.center,
        ),
        hasBackground: map['hasBackground'] as bool? ?? false,
        backgroundColor: map['backgroundColor'] as int? ?? 0xFF000000,
        backgroundOpacity: (map['backgroundOpacity'] as num?)?.toDouble() ?? 0.6,
        backgroundPadding: (map['backgroundPadding'] as num?)?.toDouble() ?? 0.1,
        backgroundCornerRadius:
            (map['backgroundCornerRadius'] as num?)?.toDouble() ?? 0.15,
      );

  /// Create a copy with modified properties.
  TextLayer copyWith({
    String? text,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    int? color,
    double? opacity,
    String? fontFamily,
    double? fontSize,
    TextAlignment? alignment,
    bool? hasBackground,
    int? backgroundColor,
    double? backgroundOpacity,
    double? backgroundPadding,
    double? backgroundCornerRadius,
  }) {
    return TextLayer(
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      alignment: alignment ?? this.alignment,
      hasBackground: hasBackground ?? this.hasBackground,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
      backgroundCornerRadius:
          backgroundCornerRadius ?? this.backgroundCornerRadius,
    );
  }

  /// Get text color as ui.Color.
  ui.Color get uiColor => ui.Color(color);

  /// Get background color as ui.Color with its own opacity.
  ui.Color get uiBackgroundColor => ui.Color(backgroundColor);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLayer &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          x == other.x &&
          y == other.y &&
          scale == other.scale &&
          rotation == other.rotation &&
          color == other.color &&
          opacity == other.opacity &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          alignment == other.alignment &&
          hasBackground == other.hasBackground &&
          backgroundColor == other.backgroundColor &&
          backgroundOpacity == other.backgroundOpacity &&
          backgroundPadding == other.backgroundPadding &&
          backgroundCornerRadius == other.backgroundCornerRadius;

  @override
  int get hashCode => Object.hash(
        text,
        x,
        y,
        scale,
        rotation,
        color,
        opacity,
        fontFamily,
        fontSize,
        alignment,
      );
}
