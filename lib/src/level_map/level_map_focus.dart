import 'package:just_game_engine/just_game_engine.dart';

/// What the Level Designer works on: the Level Map and everything under it.
///
/// While the designer is open nothing else can be picked, selected or
/// dragged, and nothing else is drawn in the viewport — not its sprite, nor
/// the markers and frames the editor draws for it. The scene tree still
/// lists it, faint, with its eye shut.
abstract final class LevelMapFocus {
  /// Whether [entity] is a level map or somewhere under one.
  static bool contains(World world, Entity entity) {
    var current = entity;
    // Bounded: a hierarchy with a loop in it is broken, but must not hang
    // the editor on every frame.
    for (var depth = 0; depth < 256; depth++) {
      if (current.hasComponent<LevelMapComponent>()) return true;
      final parentId = current.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : world.getEntity(parentId);
      if (parent == null) return false;
      current = parent;
    }
    return false;
  }
}
