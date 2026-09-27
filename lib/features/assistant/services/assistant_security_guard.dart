/// Security guardrails for the gallery assistant.
///
/// Prevents the assistant from performing dangerous operations
/// without explicit user consent. Enforces permission levels,
/// rate limits, and input validation.
class AssistantSecurityGuard {
  /// Maximum number of photos that can be affected by a single destructive action.
  static const int maxDestructiveBatchSize = 500;

  /// Maximum number of photos that can be affected by a single safe-write action.
  static const int maxSafeWriteBatchSize = 1000;

  /// Rate limit: maximum actions per minute.
  static const int maxActionsPerMinute = 30;

  /// Timestamps of recent actions for rate limiting.
  final List<DateTime> _recentActions = [];

  /// Validate that a batch action is within安全 limits.
  ///
  /// Returns null if valid, or an error message if the action should be blocked.
  String? validateBatchSize({
    required int itemCount,
    required bool isDestructive,
  }) {
    final limit =
        isDestructive ? maxDestructiveBatchSize : maxSafeWriteBatchSize;

    if (itemCount > limit) {
      return 'Cannot operate on $itemCount items at once. '
          'Maximum is $limit. '
          'Please narrow your selection.';
    }

    if (itemCount == 0) {
      return 'No items selected.';
    }

    return null;
  }

  /// Check rate limit.
  ///
  /// Returns null if within limits, or an error message if rate-limited.
  String? checkRateLimit() {
    final now = DateTime.now();
    final oneMinuteAgo = now.subtract(const Duration(minutes: 1));

    // Remove old timestamps
    _recentActions.removeWhere((t) => t.isBefore(oneMinuteAgo));

    if (_recentActions.length >= maxActionsPerMinute) {
      return 'Too many actions. Please wait a moment before trying again.';
    }

    _recentActions.add(now);
    return null;
  }

  /// Validate input text for potentially dangerous patterns.
  ///
  /// Returns null if safe, or a warning message.
  String? validateInput(String input) {
    final lower = input.toLowerCase().trim();

    // Block extremely long inputs (potential abuse)
    if (input.length > 1000) {
      return 'Input too long. Please keep queries under 1000 characters.';
    }

    // Warn about SQL injection patterns (belt-and-suspenders)
    if (lower.contains('drop table') ||
        lower.contains('delete from') ||
        lower.contains('truncate')) {
      return 'Invalid query detected.';
    }

    return null;
  }

  /// Check if a destructive action requires double confirmation.
  ///
  /// For actions affecting more than [threshold] items, require
  /// the user to type a confirmation phrase.
  bool requiresDoubleConfirmation({
    required int itemCount,
    required bool isDestructive,
    int threshold = 10,
  }) {
    return isDestructive && itemCount >= threshold;
  }

  /// Get the confirmation phrase the user must type.
  String getConfirmationPhrase(int itemCount) {
    return 'DELETE $itemCount PHOTOS';
  }

  /// Validate that the user typed the correct confirmation phrase.
  bool validateConfirmationPhrase({
    required String userInput,
    required int itemCount,
  }) {
    final expected = getConfirmationPhrase(itemCount);
    return userInput.trim().toUpperCase() == expected;
  }
}
