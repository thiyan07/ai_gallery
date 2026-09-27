/// A temporary, session-scoped result reference.
///
/// When the assistant returns search results, it stores them in a ResultSet
/// and returns only the reference ID. Subsequent queries can refer to this
/// result set by ID (e.g. "add all of those to favorites" → references the
/// previous search result set).
///
/// Result sets are:
/// - Session-scoped (never persisted to disk)
/// - Time-bounded (expire after [ttl])
/// - User-scoped (each session has its own result sets)
class ResultSet {
  /// Unique identifier for this result set.
  final String id;

  /// Photo IDs in this result set.
  final List<String> photoIds;

  /// Human-readable description of what this result set contains.
  final String description;

  /// The original query or intent that produced this result.
  final String? sourceQuery;

  /// When this result set was created.
  final DateTime createdAt;

  /// Time-to-live for this result set.
  final Duration ttl;

  ResultSet({
    required this.id,
    required this.photoIds,
    required this.description,
    this.sourceQuery,
    DateTime? createdAt,
    this.ttl = const Duration(minutes: 30),
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether this result set has expired.
  bool get isExpired => DateTime.now().difference(createdAt) > ttl;

  /// Number of photos in this result set.
  int get count => photoIds.length;
}

/// Manages session-scoped result sets for the gallery assistant.
///
/// Result sets allow the assistant to reference previous search results
/// without re-executing the query. They expire automatically after a
/// configurable TTL (default: 30 minutes).
class ResultSetManager {
  /// Active result sets keyed by ID.
  final Map<String, ResultSet> _resultSets = {};

  /// Counter for generating unique IDs.
  int _counter = 0;

  /// Default TTL for result sets.
  final Duration defaultTtl;

  ResultSetManager({this.defaultTtl = const Duration(minutes: 30)});

  /// Store a new result set and return its ID.
  String store({
    required List<String> photoIds,
    required String description,
    String? sourceQuery,
    Duration? ttl,
  }) {
    final id = 'rs_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
    _resultSets[id] = ResultSet(
      id: id,
      photoIds: photoIds,
      description: description,
      sourceQuery: sourceQuery,
      ttl: ttl ?? defaultTtl,
    );
    return id;
  }

  /// Retrieve a result set by ID, or null if not found/expired.
  ResultSet? get(String id) {
    final rs = _resultSets[id];
    if (rs == null) return null;
    if (rs.isExpired) {
      _resultSets.remove(id);
      return null;
    }
    return rs;
  }

  /// Get the photo IDs from a result set, or empty list if not found.
  List<String> getPhotoIds(String id) => get(id)?.photoIds ?? [];

  /// Get the most recent result set.
  ResultSet? get latest {
    _pruneExpired();
    if (_resultSets.isEmpty) return null;
    final sorted = _resultSets.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  /// Check if a string looks like a result set reference.
  bool isResultSetReference(String input) {
    final trimmed = input.trim().toLowerCase();
    return trimmed == 'those' ||
        trimmed == 'them' ||
        trimmed == 'all of them' ||
        trimmed == 'all of those' ||
        trimmed == 'the previous results' ||
        trimmed == 'last results' ||
        trimmed.startsWith('result set ');
  }

  /// Try to resolve a result set reference from natural language.
  ///
  /// Returns the most recent result set if the input looks like a reference
  /// to previous results.
  ResultSet? resolveReference(String input, {String? explicitId}) {
    if (explicitId != null) return get(explicitId);

    if (!isResultSetReference(input)) return null;
    return latest;
  }

  /// Prune expired result sets.
  void _pruneExpired() {
    _resultSets.removeWhere((_, rs) => rs.isExpired);
  }

  /// Clear all result sets.
  void clear() {
    _resultSets.clear();
  }

  /// Get the count of active (non-expired) result sets.
  int get activeCount {
    _pruneExpired();
    return _resultSets.length;
  }
}
