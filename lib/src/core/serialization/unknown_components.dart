import 'package:just_game_engine/just_game_engine.dart';

/// The components a scene names that no registered definition can read,
/// kept exactly as the file had them.
///
/// A scene can name a component its editor cannot decode: a module that is
/// not registered this session, or one that has moved to another package.
/// Dropping them — which is what the editor used to do — lost them for good
/// on the next save, with nothing said. Held here instead, they are written
/// back unchanged and reported as a problem.
///
/// One per entity, because an entity keeps one component per type and every
/// unknown one would otherwise land on the same key.
class UnknownComponents extends Component {
  UnknownComponents(Iterable<Map<String, dynamic>> entries)
    : entries = List.unmodifiable(entries);

  /// The saved components, each as its file stored it.
  final List<Map<String, dynamic>> entries;

  /// The type names nothing could read.
  List<String> get types => [
    for (final e in entries) e['type'] as String? ?? '(no type)',
  ];

  @override
  String toString() => 'UnknownComponents(${types.join(', ')})';
}
