import 'dart:collection';

/// A bounded LRU cache that evicts the least-recently-used entries
/// when it exceeds [maxSize]. Thread-safe for single-isolate use.
class BoundedCache<K, V> {
  BoundedCache({required int maxSize, int? evictCount})
      : _maxSize = maxSize,
        _evictCount = evictCount ?? (maxSize ~/ 4).clamp(1, 100);

  final int _maxSize;
  final int _evictCount;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  int get length => _map.length;
  bool get isEmpty => _map.isEmpty;
  bool get isFull => _map.length >= _maxSize;

  /// Returns the value for [key], promoting it to most-recently-used.
  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value; // Re-insert at end (most recent)
    }
    return value;
  }

  /// Returns the value for [key] without promoting it (peek).
  V? peek(K key) => _map[key];

  /// Inserts or updates [key] with [value]. Evicts LRU entries if over capacity.
  void put(K key, V value) {
    _map.remove(key); // Remove first to control insertion order
    _map[key] = value;
    _evictIfNeeded();
  }

  /// Removes [key] from the cache.
  V? remove(K key) => _map.remove(key);

  /// Clears all entries.
  void clear() => _map.clear();

  /// Returns all keys in access order (least recent first).
  Iterable<K> get keys => _map.keys;

  /// Returns all values in access order (least recent first).
  Iterable<V> get values => _map.values;

  /// Evicts the least-recently-used entries if over capacity.
  void _evictIfNeeded() {
    while (_map.length > _maxSize) {
      // Remove the first entry (least recently used)
      _map.keys.first;
      final iterator = _map.keys.iterator;
      if (iterator.moveNext()) {
        _map.remove(iterator.current);
      }
    }
  }

  /// Performs bulk eviction, removing [_evictCount] LRU entries.
  void evict() {
    var removed = 0;
    final iterator = _map.keys.iterator;
    while (removed < _evictCount && iterator.moveNext()) {
      // Can't remove during iteration, collect keys first
    }
    final keysToRemove = _map.keys.take(_evictCount).toList();
    for (final key in keysToRemove) {
      _map.remove(key);
    }
  }
}
