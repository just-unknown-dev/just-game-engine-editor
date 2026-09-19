/// Hands out entity names nothing else has.
///
/// Unique against the world *and* against every name already handed out.
/// Tools name a whole batch — a paint stroke's merged rectangles, a
/// multi-entity duplicate — before creating any of it, so checking the world
/// alone gave every entity in the batch the same name. Parents are linked by
/// name when a level loads, so a duplicate name is not cosmetic.
class UniqueNamer {
  UniqueNamer(this._existingNames);

  final Iterable<String> Function() _existingNames;
  final Set<String> _issued = {};

  /// A name of the form `prefix_N` that is not in use and has not been
  /// issued before.
  String call(String prefix) {
    final taken = {..._existingNames(), ..._issued};
    var index = 0;
    var candidate = '${prefix}_$index';
    while (taken.contains(candidate)) {
      index++;
      candidate = '${prefix}_$index';
    }
    _issued.add(candidate);
    return candidate;
  }
}
