import '../models/gallery_intent.dart';

/// Represents a single step in a multi-step action plan.
class ActionPlanStep {
  final GalleryIntent intent;
  final String query;
  final Map<String, dynamic> parameters;

  const ActionPlanStep({
    required this.intent,
    required this.query,
    this.parameters = const {},
  });
}

/// Detects and decomposes compound user requests into sequential steps.
///
/// Handles patterns like:
/// - "find beach photos and create an album"
/// - "search for cats then add them to favorites"
/// - "find best photos from last month and make a memory"
class MultiStepPlanner {
  /// Splitter patterns that indicate compound requests.
  static final _compoundPatterns = RegExp(
    r'\b(?:and|then|also|after that|next)\b',
    caseSensitive: false,
  );

  /// Detects if a raw user query is a compound request.
  bool isCompoundRequest(String rawText) {
    final lower = rawText.toLowerCase();
    // Must have a splitter AND at least one action keyword after it
    if (!_compoundPatterns.hasMatch(lower)) return false;

    // Check for action keywords (create, add, remove, delete)
    final actionKeywords = RegExp(
      r'\b(?:create|make|add|remove|delete|favorite|album|memory)\b',
      caseSensitive: false,
    );
    return actionKeywords.hasMatch(lower);
  }

  /// Decompose a compound request into sequential steps.
  ///
  /// Returns a list of [ActionPlanStep] that should be executed in order.
  /// The result of each step can be passed to the next via result sets.
  List<ActionPlanStep> decompose(String rawText, GalleryIntent primaryIntent) {
    if (!isCompoundRequest(rawText)) {
      return [ActionPlanStep(intent: primaryIntent, query: rawText)];
    }

    // Split on compound patterns
    final parts = rawText.split(_compoundPatterns).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (parts.length < 2) {
      return [ActionPlanStep(intent: primaryIntent, query: rawText)];
    }

    final steps = <ActionPlanStep>[];
    for (final part in parts) {
      final stepIntent = _classifyStep(part);
      steps.add(ActionPlanStep(intent: stepIntent, query: part));
    }

    return steps;
  }

  /// Classify the intent of a single step within a compound request.
  GalleryIntent _classifyStep(String text) {
    final lower = text.toLowerCase();

    if (RegExp(r'\b(?:album|collection)\b').hasMatch(lower)) {
      return GalleryIntent.createAlbum;
    }
    if (RegExp(r'\b(?:memory|memories)\b').hasMatch(lower)) {
      return GalleryIntent.createMemory;
    }
    if (RegExp(r'\b(?:favori|like|heart)\b').hasMatch(lower)) {
      return GalleryIntent.addToFavorites;
    }
    if (RegExp(r'\b(?:unfavori|unlike|remove)\b').hasMatch(lower)) {
      return GalleryIntent.removeFromFavorites;
    }
    if (RegExp(r'\b(?:delete|remove|trash)\b').hasMatch(lower)) {
      return GalleryIntent.deletePhotos;
    }

    // Default to search
    return GalleryIntent.textSearch;
  }

  /// Get a human-readable description of the plan.
  String describePlan(List<ActionPlanStep> steps) {
    if (steps.length == 1) return steps.first.query;
    return steps.asMap().entries.map((e) {
      final i = e.key + 1;
      final step = e.value;
      return '$i. ${step.query}';
    }).join('\n');
  }
}
