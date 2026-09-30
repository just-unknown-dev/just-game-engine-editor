import 'package:just_game_engine/just_game_engine.dart' as jge;

/// What an editor shows in each scene mode — one place, so the inspector,
/// the timeline and the pickers agree.
abstract final class SceneModeFilters {
  /// Which of [field]'s channels show in [mode]: all of them in 3-D; in 2-D
  /// the hint's own choice, else the type's ([jge.FieldType.channels2D]) —
  /// a position's x and y, a rotation's z. Hidden ones keep their values.
  static Set<String> visibleChannels(
    jge.SchemaField field,
    jge.FieldHint? hint,
    jge.SceneMode mode,
  ) {
    final all = field.kind.channels;
    if (mode == jge.SceneMode.threeD) return all.toSet();
    return hint?.channels2D ?? field.kind.channels2D;
  }

  /// Whether a field with [hint] is shown at all in [mode].
  static bool fieldShown(jge.FieldHint? hint, jge.SceneMode mode) =>
      hint == null || hint.dimensions.allows(mode);

  /// Whether a component with [hints] is offered — in a picker, say — in
  /// [mode]. One already on an entity is shown regardless.
  static bool componentOffered(jge.ComponentHints? hints, jge.SceneMode mode) =>
      hints == null || hints.dimensions.allows(mode);
}
