import 'dart:async';
import 'dart:collection';

/// Textures kept by key for drawing again — the maps a material picture
/// uploaded — the least recently used let go first once those ready come
/// to more than [budget] bytes.
///
/// A texture is let go by dropping it: the GPU memory it holds is freed
/// once nothing else holds it. The textures one drawing uses (its `keep`)
/// are never let go to make room for each other, whatever they come to, so
/// a drawing that needs more than the budget still finds all of them the
/// next time.
final class TextureCache<K, T extends Object> {
  /// A cache keeping at most [budget] bytes, each texture's size given by
  /// [sizeOf].
  TextureCache({required this.budget, required this.sizeOf});

  /// The most bytes kept, but for one drawing's own textures.
  final int budget;

  /// How many bytes a texture holds.
  final int Function(T texture) sizeOf;

  // Least recently used first.
  final LinkedHashMap<K, Future<T?>> _entries = LinkedHashMap();
  // The size of each that is ready.
  final Map<K, int> _bytes = {};

  /// How many bytes the textures kept and ready hold.
  int get bytes => _bytes.values.fold(0, (sum, b) => sum + b);

  /// The keys kept, the least recently used first.
  Iterable<K> get keys => _entries.keys;

  /// Whether [key] is kept (or being made).
  bool contains(K key) => _entries.containsKey(key);

  /// The texture at [key]: kept, or made by [load] — once, however many
  /// ask meanwhile. When it is ready, the least recently used of the
  /// others are let go until what is kept fits the [budget], but never
  /// [keep]'s: the other textures of the same drawing.
  ///
  /// A [load] that throws keeps nothing, so the next ask tries again; one
  /// that gives null (nothing to upload) is kept as that.
  Future<T?> get(K key, Future<T?> Function() load, {Set<K> keep = const {}}) {
    final known = _entries.remove(key);
    if (known != null) {
      // The most recently used now.
      _entries[key] = known;
      return known;
    }
    final done = Completer<T?>();
    final future = done.future;
    _entries[key] = future;
    Future.sync(load).then(
      (texture) {
        if (identical(_entries[key], future)) {
          _bytes[key] = texture == null ? 0 : sizeOf(texture);
          _trim({...keep, key});
        }
        done.complete(texture);
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_entries[key], future)) _entries.remove(key);
        done.completeError(error, stack);
      },
    );
    return future;
  }

  /// Lets go of the textures whose keys [test] picks.
  void removeWhere(bool Function(K key) test) {
    for (final key in _entries.keys.where(test).toList()) {
      _entries.remove(key);
      _bytes.remove(key);
    }
  }

  /// Lets go of every texture.
  void clear() {
    _entries.clear();
    _bytes.clear();
  }

  void _trim(Set<K> keep) {
    var total = bytes;
    if (total <= budget) return;
    for (final key in _entries.keys.toList()) {
      if (total <= budget) return;
      if (keep.contains(key)) continue;
      // Still being made: its size is not known yet.
      final size = _bytes[key];
      if (size == null) continue;
      _entries.remove(key);
      _bytes.remove(key);
      total -= size;
    }
  }
}
