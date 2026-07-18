import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages the set of currently selected asset IDs for multi-select mode.
final selectionProvider =
    NotifierProvider<SelectionNotifier, Set<String>>(SelectionNotifier.new);

class SelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  /// Whether multi-select mode is active.
  bool get isActive => state.isNotEmpty;

  /// Toggle a single asset's selection state.
  void toggle(String assetId) {
    if (state.contains(assetId)) {
      state = {...state}..remove(assetId);
    } else {
      state = {...state, assetId};
    }
  }

  /// Select all provided asset IDs.
  void selectAll(List<String> ids) {
    state = ids.toSet();
  }

  /// Clear the entire selection.
  void clear() => state = {};
}
