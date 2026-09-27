import 'dart:math';

/// Explains why a photo matched a search query.
///
/// Provides transparency into the ranking engine's decisions,
/// helping users understand and refine their searches.
class SearchExplainer {
  /// Generate explanations for why a photo appears in search results.
  List<SearchExplanation> explain({
    required String photoId,
    required String query,
    required Map<String, double> signalScores,
    required double finalScore,
  }) {
    final explanations = <SearchExplanation>[];

    // Text/label match
    if (signalScores.containsKey('textMatch') && signalScores['textMatch']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.textLabelMatch,
        strength: signalScores['textMatch']!,
        description: 'Photo matches text query',
      ));
    }

    // Object detection match
    if (signalScores.containsKey('objectMatch') &&
        signalScores['objectMatch']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.objectDetection,
        strength: signalScores['objectMatch']!,
        description: 'Contains recognized objects',
      ));
    }

    // Face/person match
    if (signalScores.containsKey('faceMatch') && signalScores['faceMatch']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.personMatch,
        strength: signalScores['faceMatch']!,
        description: 'Contains matching person',
      ));
    }

    // Semantic similarity
    if (signalScores.containsKey('semantic') && signalScores['semantic']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.semanticSimilarity,
        strength: signalScores['semantic']!,
        description: 'Semantically similar to query',
      ));
    }

    // Location match
    if (signalScores.containsKey('location') && signalScores['location']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.locationMatch,
        strength: signalScores['location']!,
        description: 'Matches location criteria',
      ));
    }

    // Date/time match
    if (signalScores.containsKey('date') && signalScores['date']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.dateMatch,
        strength: signalScores['date']!,
        description: 'Matches date/time criteria',
      ));
    }

    // Quality signal
    if (signalScores.containsKey('quality') && signalScores['quality']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.qualityBoost,
        strength: signalScores['quality']!,
        description: 'Higher quality photo',
      ));
    }

    // Recency signal
    if (signalScores.containsKey('recency') && signalScores['recency']! > 0) {
      explanations.add(SearchExplanation(
        signal: SearchSignal.recencyBoost,
        strength: signalScores['recency']!,
        description: 'More recent photo',
      ));
    }

    // Sort by strength
    explanations.sort((a, b) => b.strength.compareTo(a.strength));

    return explanations;
  }

  /// Generate a human-readable summary of search results.
  String summarizeResults(List<SearchExplanation> topExplanations) {
    if (topExplanations.isEmpty) return 'No specific signals matched.';

    final primary = topExplanations.first;
    final others = topExplanations.length - 1;

    final buffer = StringBuffer(primary.description);
    if (others > 0) {
      buffer.write(' (+$others other signals)');
    }
    return buffer.toString();
  }
}

/// A single explanation for why a photo matched.
class SearchExplanation {
  final SearchSignal signal;
  final double strength;
  final String description;

  const SearchExplanation({
    required this.signal,
    required this.strength,
    required this.description,
  });

  String get strengthLabel {
    if (strength > 0.8) return 'Strong match';
    if (strength > 0.5) return 'Moderate match';
    if (strength > 0.2) return 'Weak match';
    return 'Minimal match';
  }
}

/// Types of signals that can contribute to search ranking.
enum SearchSignal {
  textLabelMatch,
  objectDetection,
  personMatch,
  semanticSimilarity,
  locationMatch,
  dateMatch,
  qualityBoost,
  recencyBoost,
}
