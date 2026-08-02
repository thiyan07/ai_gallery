import 'dart:async';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:sqflite/sqflite.dart';

/// Search suggestion entry.
class SearchSuggestion {
  const SearchSuggestion({
    required this.query,
    required this.timestamp,
    this.count = 1,
    this.type = SuggestionType.recent,
    this.metadata,
  });

  final String query;
  final DateTime timestamp;
  final int count;
  final SuggestionType type;
  final Map<String, dynamic>? metadata;

  SearchSuggestion copyWith({
    String? query,
    DateTime? timestamp,
    int? count,
    SuggestionType? type,
    Map<String, dynamic>? metadata,
  }) {
    return SearchSuggestion(
      query: query ?? this.query,
      timestamp: timestamp ?? this.timestamp,
      count: count ?? this.count,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'timestamp': timestamp.toIso8601String(),
        'count': count,
        'type': type.name,
        'metadata': metadata,
      };

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) {
    return SearchSuggestion(
      query: json['query'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      count: json['count'] as int? ?? 1,
      type: SuggestionType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'recent'),
        orElse: () => SuggestionType.recent,
      ),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

enum SuggestionType {
  recent,
  suggested,
  autoComplete,
  popular,
}

/// Service for managing search suggestions (recent, popular, auto-complete).
class SearchSuggestionService {
  SearchSuggestionService({
    required this.database,
    AppLogger? logger,
  }) : _logger = logger ?? const ConsoleAppLogger();

  final AppDatabase database;
  final AppLogger _logger;

  /// Maximum suggestions to store.
  static const _maxSuggestions = 100;

  /// Table name for search history.
  static const _tableName = 'search_history';

  /// Initializes the search history table.
  Future<void> initialize() async {
    await database.database.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL DEFAULT 'recent',
        metadata TEXT
      )
    ''');
    // Index for fast lookups
    await database.database.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_history_query ON $_tableName(query)
    ''');
    await database.database.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_history_timestamp ON $_tableName(timestamp DESC)
    ''');
    await database.database.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_history_type ON $_tableName(type)
    ''');
    _logger.info('Search suggestion table initialized');
  }

  /// Records a search query (updates count if exists, inserts if new).
  Future<void> recordSearch(String query, {SuggestionType type = SuggestionType.recent}) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return;

    // Check if exists
    final existing = await database.database.query(
      _tableName,
      where: 'query = ?',
      whereArgs: [trimmed],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update count and timestamp
      final row = existing.first;
      final newCount = (row['count'] as int) + 1;
      await database.database.update(
        _tableName,
        {
          'count': newCount,
          'timestamp': DateTime.now().toIso8601String(),
          'type': type.name,
        },
        where: 'query = ?',
        whereArgs: [trimmed],
      );
    } else {
      // Insert new
      await database.database.insert(
        _tableName,
        {
          'query': trimmed,
          'timestamp': DateTime.now().toIso8601String(),
          'count': 1,
          'type': type.name,
        },
      );
    }

    // Prune old entries if over limit
    await _pruneOldEntries();
  }

  /// Gets recent searches (most recent first).
  Future<List<SearchSuggestion>> getRecentSearches({int limit = 10}) async {
    final rows = await database.database.query(
      _tableName,
      where: 'type = ?',
      whereArgs: [SuggestionType.recent.name],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(_rowToSuggestion).toList();
  }

  /// Gets popular searches (highest count first).
  Future<List<SearchSuggestion>> getPopularSearches({int limit = 10}) async {
    final rows = await database.database.query(
      _tableName,
      orderBy: 'count DESC, timestamp DESC',
      limit: limit,
    );
    return rows.map(_rowToSuggestion).toList();
  }

  /// Gets auto-complete suggestions for a prefix.
  Future<List<SearchSuggestion>> getAutoCompleteSuggestions(
    String prefix, {
    int limit = 5,
  }) async {
    final trimmed = prefix.trim().toLowerCase();
    if (trimmed.isEmpty) return [];

    final rows = await database.database.query(
      _tableName,
      where: 'query LIKE ?',
      whereArgs: ['$trimmed%'],
      orderBy: 'count DESC, timestamp DESC',
      limit: limit,
    );
    return rows.map(_rowToSuggestion).toList();
  }

  /// Gets suggested searches based on patterns (time-based, seasonal, etc.).
  Future<List<SearchSuggestion>> getSuggestedSearches({int limit = 5}) async {
    // For now, return popular searches that haven't been searched recently
    final recent = await getRecentSearches(limit: 20);
    final recentQueries = recent.map((s) => s.query).toSet();

    final allPopular = await getPopularSearches(limit: limit * 3);
    final suggestions = allPopular
        .where((s) => !recentQueries.contains(s.query))
        .take(limit)
        .toList();

    // Add some contextual suggestions if we have few
    if (suggestions.length < limit) {
      final contextual = _generateContextualSuggestions(
        exclude: recentQueries.union(suggestions.map((s) => s.query).toSet()),
        limit: limit - suggestions.length,
      );
      suggestions.addAll(contextual);
    }

    return suggestions.take(limit).toList();
  }

  /// Generates contextual suggestions based on time/season.
  List<SearchSuggestion> _generateContextualSuggestions({
    required Set<String> exclude,
    required int limit,
  }) {
    final now = DateTime.now();
    final suggestions = <SearchSuggestion>[];

    // Seasonal suggestions
    final month = now.month;
    final seasonal = <String>[
      if (month >= 3 && month <= 5) 'spring flowers',
      if (month >= 6 && month <= 8) 'summer beach sunset',
      if (month >= 9 && month <= 11) 'autumn leaves',
      if (month >= 12 || month <= 2) 'winter snow',
    ];

    // Time-based suggestions
    final hour = now.hour;
    if (hour >= 5 && hour <= 8) suggestions.add(SearchSuggestion(query: 'sunrise', timestamp: now, type: SuggestionType.suggested));
    if (hour >= 17 && hour <= 20) suggestions.add(SearchSuggestion(query: 'golden hour photos', timestamp: now, type: SuggestionType.suggested));
    if (hour >= 21 || hour <= 4) suggestions.add(SearchSuggestion(query: 'night photography', timestamp: now, type: SuggestionType.suggested));

    // Filter and add
    for (final s in seasonal) {
      if (suggestions.length >= limit) break;
      final lower = s.toLowerCase();
      if (!exclude.contains(lower)) {
        suggestions.add(SearchSuggestion(
          query: s,
          timestamp: now,
          type: SuggestionType.suggested,
        ));
        exclude.add(lower);
      }
    }

    return suggestions;
  }

  /// Deletes a specific search from history.
  Future<void> deleteSearch(String query) async {
    await database.database.delete(
      _tableName,
      where: 'query = ?',
      whereArgs: [query.trim().toLowerCase()],
    );
  }

  /// Clears all search history.
  Future<void> clearHistory() async {
    await database.database.delete(_tableName);
  }

  /// Prunes old entries to keep table size manageable.
  Future<void> _pruneOldEntries() async {
    final count = Sqflite.firstIntValue(
      await database.database.rawQuery('SELECT COUNT(*) FROM $_tableName'),
    ) ?? 0;

    if (count > _maxSuggestions) {
      await database.database.rawDelete('''
        DELETE FROM $_tableName
        WHERE id NOT IN (
          SELECT id FROM $_tableName
          ORDER BY count DESC, timestamp DESC
          LIMIT $_maxSuggestions
        )
      ''');
    }
  }

  SearchSuggestion _rowToSuggestion(Map<String, dynamic> row) {
    return SearchSuggestion(
      query: row['query'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String),
      count: row['count'] as int,
      type: SuggestionType.values.firstWhere(
        (e) => e.name == (row['type'] as String? ?? 'recent'),
        orElse: () => SuggestionType.recent,
      ),
    );
  }
}