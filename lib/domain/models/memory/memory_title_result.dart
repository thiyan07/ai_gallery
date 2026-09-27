/// Result of generating a title for a memory candidate.
class MemoryTitleResult {
  final String title;
  final String? subtitle;
  final String theme;
  final double confidence;
  final bool usesDate;
  final bool usesLocation;
  final bool usesPeople;
  final bool usesEvent;

  const MemoryTitleResult({
    required this.title,
    this.subtitle,
    required this.theme,
    this.confidence = 0.0,
    this.usesDate = false,
    this.usesLocation = false,
    this.usesPeople = false,
    this.usesEvent = false,
  });
}
