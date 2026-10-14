import 'package:flutter/material.dart' show IconData, Icons;
import 'package:just_game_engine/just_game_engine.dart';

/// Which gizmo the selection shows: the floating toolbar's buttons, Q, W,
/// E and R. One for the editor and the Level Designer alike.
enum TransformMode {
  /// Move, scale and turn with one gizmo — how the editor and the designer
  /// always worked, and where they start.
  all('All', Icons.near_me, 'editor.transform.all'),
  move('Move', Icons.open_with, 'editor.transform.move'),
  scale('Scale', Icons.aspect_ratio, 'editor.transform.scale'),
  rotate('Rotate', Icons.rotate_right, 'editor.transform.rotate');

  const TransformMode(this.label, this.icon, this.commandId);

  final String label;
  final IconData icon;

  /// The command that picks it, and so the key bound to that.
  final String commandId;
}

/// Which modes what is selected can take.
abstract final class TransformModes {
  static const Set<TransformMode> none = {};

  /// Tiles picked with Select tiles: moved, or turned a quarter at a time.
  /// A tile has no size of its own to scale.
  static const Set<TransformMode> tiles = {
    TransformMode.all,
    TransformMode.move,
    TransformMode.rotate,
  };

  /// What [entities] can take. Only what is in the world counts: a piece of
  /// interface has no transform. A level map follows its position and
  /// nothing else, so it moves; a piece cut from one also turns, its tiles
  /// a quarter at a time, when it is all that is selected and
  /// [turnsPieces] — only the Level Designer can; nothing that includes a
  /// map scales. All is there whenever anything is: it shows what applies.
  static Set<TransformMode> forEntities(
    World world,
    List<Entity> entities, {
    bool turnsPieces = true,
  }) {
    final placed = [
      for (final e in entities)
        if (e.hasComponent<TransformComponent>()) e,
    ];
    if (placed.isEmpty) return none;
    if (!placed.any((e) => e.hasComponent<LevelMapComponent>())) {
      return TransformMode.values.toSet();
    }
    final onePiece =
        turnsPieces &&
        placed.length == 1 &&
        LevelMaps.isPiece(world, placed.single);
    return {
      TransformMode.all,
      TransformMode.move,
      if (onePiece) TransformMode.rotate,
    };
  }

  /// The gizmo to show for [wanted] when [available] is what the selection
  /// can take: [wanted] itself, else All — which shows what does apply —
  /// else none at all.
  static TransformMode? shown(
    TransformMode wanted,
    Set<TransformMode> available,
  ) => available.contains(wanted)
      ? wanted
      : available.contains(TransformMode.all)
      ? TransformMode.all
      : null;
}
