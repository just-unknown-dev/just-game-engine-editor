import 'dart:convert';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../ui/level_designer/state/editor_commands.dart';
import '../../ui/level_designer/state/editor_history.dart';
import '../scope/editor_scope.dart';

/// An edit of one component made by code — a handle dragged, a collider
/// fitted, a preset applied — recorded as one undo step of every saved
/// field it changed, whatever those were.
///
/// ```dart
/// final edit = ComponentEdit.begin(scope, collider);
/// collider.size = Vector2(64, 20);
/// edit.commit('Fit collider');
/// ```
final class ComponentEdit {
  ComponentEdit._(this.scope, this.component, this._before);

  /// Remembers [component]'s saved fields, before changing it.
  factory ComponentEdit.begin(EditorScope scope, jge.Component component) =>
      ComponentEdit._(scope, component, snapshot(scope, component));

  /// The editor.
  final EditorScope scope;

  /// What is edited.
  final jge.Component component;

  final Map<String, Object?>? _before;

  /// Records what changed since [ComponentEdit.begin] as one undo step
  /// called [label] — nothing when nothing did. Whether anything did.
  bool commit(String label) {
    final before = _before;
    final definition = scope.definitions.definitionFor(component);
    if (before == null || definition == null) return false;
    final commands = <EditorCommand>[];
    for (final field in definition.fields) {
      if (field.write == null || !before.containsKey(field.name)) continue;
      final after = _copy(field.encodeFrom(component));
      if (jsonEncode(after) == jsonEncode(before[field.name])) continue;
      commands.add(
        ComponentFieldCommand(
          label: '$label: ${field.name}',
          component: component,
          write: (c, v) => field.decodeInto(c, v),
          before: before[field.name],
          after: after,
          sceneState: scope.sceneState,
        ),
      );
    }
    if (commands.isEmpty) return false;
    scope.history.pushApplied(CompositeCommand(label: label, commands: commands));
    scope.sceneState
      ..markDirty()
      ..refresh();
    return true;
  }

  /// Every saved field of [component], as saved (deep-copied); null for a
  /// component with no definition.
  static Map<String, Object?>? snapshot(EditorScope scope, jge.Component component) {
    final definition = scope.definitions.definitionFor(component);
    if (definition == null) return null;
    return {
      for (final field in definition.fields)
        if (field.write != null) field.name: _copy(field.encodeFrom(component)),
    };
  }

  static Object? _copy(Object? value) => jsonDecode(jsonEncode(value));
}
