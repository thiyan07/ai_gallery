/// Result of image quality/feature analysis.
class ImageAnalysis {
  const ImageAnalysis({
    this.isBlurry = false,
    this.blurScore = 0.0,
    this.dominantColors = const {},
    this.isLowLight = false,
    this.brightness = 0.0,
  });

  final bool isBlurry;
  final double blurScore;
  final Map<String, int> dominantColors;
  final bool isLowLight;
  final double brightness;
}