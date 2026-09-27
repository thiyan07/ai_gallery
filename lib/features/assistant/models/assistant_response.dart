import 'gallery_action.dart';
import 'gallery_intent.dart';

/// A response from the gallery assistant.
///
/// Every response is grounded in actual gallery data.
/// The assistant never fabricates information.
class AssistantResponse {
  /// The natural language response text.
  final String text;

  /// The detected intent.
  final GalleryIntent intent;

  /// Photo IDs that are part of this response.
  final List<String> photoIds;

  /// Structured data supporting the response.
  final Map<String, dynamic> evidence;

  /// Confidence in this response (0.0–1.0).
  final double confidence;

  /// Suggested follow-up actions.
  final List<GalleryAction> suggestedActions;

  /// Whether this is a partial/uncertain result.
  final bool isUncertain;

  /// Human-readable explanation of why these results were returned.
  final String? explanation;

  /// Reference ID for the result set (if photos were returned).
  final String? resultSetId;

  const AssistantResponse({
    required this.text,
    required this.intent,
    this.photoIds = const [],
    this.evidence = const {},
    this.confidence = 1.0,
    this.suggestedActions = const [],
    this.isUncertain = false,
    this.explanation,
    this.resultSetId,
  });

  /// Create a "no results" response.
  factory AssistantResponse.noResults({
    required String query,
    String? reason,
  }) {
    return AssistantResponse(
      text: reason ?? 'I couldn\'t find any photos matching "$query".',
      intent: GalleryIntent.search,
      confidence: 1.0,
      isUncertain: false,
    );
  }

  /// Create a count response.
  factory AssistantResponse.count({
    required int count,
    required String description,
    List<String> photoIds = const [],
  }) {
    return AssistantResponse(
      text: 'You have $count $description.',
      intent: GalleryIntent.count,
      photoIds: photoIds,
      evidence: {'count': count, 'description': description},
      confidence: 1.0,
    );
  }

  /// Create a statistics response.
  factory AssistantResponse.statistics({
    required String text,
    required Map<String, dynamic> data,
  }) {
    return AssistantResponse(
      text: text,
      intent: GalleryIntent.statistics,
      evidence: data,
      confidence: 1.0,
    );
  }

  /// Create an uncertain/ambiguous response.
  factory AssistantResponse.ambiguous({
    required String text,
    List<GalleryAction> suggestedActions = const [],
  }) {
    return AssistantResponse(
      text: text,
      intent: GalleryIntent.unknown,
      confidence: 0.5,
      isUncertain: true,
      suggestedActions: suggestedActions,
    );
  }

  /// Create an error response.
  factory AssistantResponse.error(String message) {
    return AssistantResponse(
      text: 'Sorry, I encountered an error: $message',
      intent: GalleryIntent.unknown,
      confidence: 0.0,
    );
  }
}
