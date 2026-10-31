import 'dart:collection';

/// Bounded least-recently-used caches shared by the artwork readers. Keeping
/// futures here also prevents duplicate in-flight decodes of the same art.
class ArtCache<K, V> extends MapBase<K, V> {
  ArtCache(this.capacity, {this.maxWeight}) {
    registerArtEvictor((path) {
      for (final key in keys) {
        if (key == path || (key is String && key.startsWith('$path#'))) {
          remove(key);
        }
      }
    });
  }
  final int capacity;
  final int? maxWeight;
  final _weights = <K, int>{};
  int _weight = 0;
  void setWeight(K key, int weight) {
    if (!_items.containsKey(key)) return;
    _weight += weight - (_weights[key] ?? 0);
    _weights[key] = weight;
    _trim();
  }

  void _trim() {
    while (_items.length > capacity ||
        (maxWeight != null && _weight > maxWeight!)) {
      remove(_items.keys.first);
    }
  }

  final _items = <K, V>{};
  @override
  V? operator [](Object? key) {
    if (!_items.containsKey(key)) return null;
    final value = _items.remove(key) as V;
    _items[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, V value) {
    remove(key);
    _items[key] = value;
    _trim();
  }

  @override
  Iterable<K> get keys => List<K>.of(_items.keys);
  @override
  V? remove(Object? key) {
    _weight -= _weights.remove(key) ?? 0;
    return _items.remove(key);
  }

  @override
  void clear() {
    _items.clear();
    _weights.clear();
    _weight = 0;
  }
}

final _artEvictors = <void Function(String)>[];
void registerArtEvictor(void Function(String) evict) => _artEvictors.add(evict);
void evictArtwork(String path) {
  for (final evict in _artEvictors) {
    evict(path);
  }
}
