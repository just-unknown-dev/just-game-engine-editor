/// Undoable changes to the tags entities carry.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// The edits the inspector, the scene tree and the Problems dock make to an
/// entity's tags — each one step on the undo stack.
abstract final class TagEdits {
  /// The command that makes [entity] carry exactly [tags], or null when it
  /// already does. Adds a [jge.TagComponent] when it has none.
  static EditorCommand? setTags(
    jge.Entity entity,
    List<String> tags,
    EditorSceneState sceneState,
  ) {
    final next = jge.TagNames.normalize(tags).toList();
    final existing = entity.getComponent<jge.TagComponent>();
    if (existing == null) {
      if (next.isEmpty) return null;
      return AddComponentCommand(
        entity: entity,
        component: jge.TagComponent.of(next),
        sceneState: sceneState,
      );
    }
    final before = existing.tags.toList();
    if (listEquals(before, next)) return null;
    return ComponentFieldCommand(
      // One label per change, so two edits in a row stay two undo steps.
      label: _describe(before, next),
      component: existing,
      entity: entity,
      write: (c, v) =>
          (c as jge.TagComponent).tags = (v as List).cast<String>(),
      before: before,
      after: next,
      sceneState: sceneState,
    );
  }

  /// Pushes [setTags] onto [history]. Returns whether anything changed.
  static bool apply(
    EditorHistory history,
    jge.Entity entity,
    List<String> tags,
    EditorSceneState sceneState,
  ) {
    final command = setTags(entity, tags, sceneState);
    if (command == null) return false;
    history.push(command);
    return true;
  }

  static String _describe(List<String> before, List<String> after) {
    final added = [
      for (final t in after)
        if (!before.contains(t)) t,
    ];
    final removed = [
      for (final t in before)
        if (!after.contains(t)) t,
    ];
    if (added.length == 1 && removed.isEmpty) return 'Add tag "${added[0]}"';
    if (removed.length == 1 && added.isEmpty) {
      return 'Remove tag "${removed[0]}"';
    }
    if (added.length == 1 && removed.length == 1) {
      return 'Change tag "${removed[0]}" to "${added[0]}"';
    }
    return 'Change tags';
  }
}
