/// Permission level required to execute an assistant action.
enum ActionPermissionLevel {
  /// Read-only actions (search, count, stats, navigate). Always allowed.
  read,

  /// Safe write actions (add favorites, create album, create memory).
  /// Single confirmation.
  safeWrite,

  /// Destructive actions (delete photos, remove favorites).
  /// Double confirmation required.
  destructive,
}

/// Lifecycle state of a tracked assistant action.
enum ActionStatus {
  /// Action has been planned but not yet confirmed by user.
  planned,

  /// Action is waiting for user confirmation.
  awaitingConfirmation,

  /// User confirmed; action is ready to execute.
  confirmed,

  /// Action is currently executing.
  executing,

  /// Action completed successfully.
  completed,

  /// Action failed during execution.
  failed,

  /// User cancelled the action before execution.
  cancelled,

  /// Action was undone by the user.
  undone,
}

/// Result type returned by action execution.
enum ActionResultType {
  /// Action completed successfully.
  success,

  /// Action failed.
  failure,

  /// Action requires user confirmation before proceeding.
  confirmationRequired,

  /// Action produces a navigation result (open photo, etc.).
  navigation,

  /// Action returned a read-only result (count, stats, search results).
  informational,
}
