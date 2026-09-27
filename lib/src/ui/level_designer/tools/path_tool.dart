import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/state/editor_scene_state.dart';
import '../state/editor_commands.dart';
import '../state/editor_history.dart';
import 'level_tool.dart';

/// Tells [PathTool] which component on an entity owns a path, and how to read
/// and write it.
///
/// The editor has no idea what a patrol route or a camera rail is — but "a
/// component on the selection holding a `List<Offset>`" is a shape it can edit
/// generically. A project supplies this binding and gets canvas path editing
/// for its own component for free.
class PathBinding {
  const PathBinding({
    required this.resolve,
    required this.read,
    required this.write,
    this.isClosed,
    this.minimumPoints = 2,
    this.emptyMessage = 'Select something with an editable path',
    this.tooFewPointsMessage = 'A path needs at least two points',
  });

  /// Finds the path-owning component on [entity], or null if it has none.
  final jge.Component? Function(jge.Entity entity) resolve;

  /// Reads the current waypoints.
  final List<Offset> Function(jge.Component component) read;

  /// Writes waypoints back. Must copy — the tool reuses its lists.
  final void Function(jge.Component component, List<Offset> points) write;

  /// Whether the path loops back to its first point, so the tool can draw and
  /// reason about it as closed. Null means always open.
  final bool Function(jge.Component component)? isClosed;

  /// Below this, the tool refuses to remove a point.
  final int minimumPoints;

  /// Shown when the selection has no path-owning component.
  final String emptyMessage;

  /// Shown when a removal would go below [minimumPoints].
  final String tooFewPointsMessage;
}

/// Edits a component's waypoint path directly on the canvas.
///
/// The inspector can already edit the list numerically, which is fine for
/// nudging a value and useless for authoring a route — you cannot see where the
/// thing will go. Dragging the points in place is how a path gets designed.
///
/// Drag an existing point to move it, click empty space to append one,
/// Ctrl+click a point to delete it.
class PathTool extends LevelToolHandler {
  PathTool({
    required this.sceneState,
    required this.history,
    required this.binding,
    String id = 'path',
    String label = 'Path',
    IconData icon = Icons.route,
    String? shortcut = 'E',
    String? description,
    int order = 40,
    String group = ToolGroups.select,
  }) : _id = id,
       _label = label,
       _icon = icon,
       _shortcut = shortcut,
       _description = description,
       _order = order,
       _group = group;

  /// Shared selection and dirty state.
  final EditorSceneState sceneState;

  /// Where waypoint edits are recorded.
  final EditorHistory history;

  /// What counts as a path, and how to read and write it.
  final PathBinding binding;

  final String _id;
  final String _label;
  final IconData _icon;
  final String? _shortcut;
  final String? _description;
  final int _order;
  final String _group;

  @override
  String get id => _id;

  @override
  String get label => _label;

  @override
  IconData get icon => _icon;

  @override
  String? get shortcut => _shortcut;

  @override
  String? get description =>
      _description ?? 'Drag waypoints; click to add, Ctrl+click to remove';

  @override
  int get order => _order;

  @override
  String get group => _group;

  /// How close, in world units, a click must be to grab a waypoint.
  static const double grabRadius = 18.0;

  jge.Component? _target;
  int _pointIndex = -1;
  List<Offset> _before = const [];

  @override
  bool onPointerDown(ToolContext context) {
    final target = _selectedPathComponent();
    if (target == null) {
      context.controller.setStatus(binding.emptyMessage);
      return false;
    }

    _target = target;
    _before = List.of(binding.read(target));

    final index = _pointNear(target, context.worldPosition);

    if (index >= 0 && context.isCtrlDown) {
      if (_before.length <= binding.minimumPoints) {
        context.controller.setStatus(binding.tooFewPointsMessage);
        _target = null;
        return true;
      }
      final next = List.of(_before)..removeAt(index);
      _commit(next, 'Remove waypoint');
      _target = null;
      return true;
    }

    if (index >= 0) {
      _pointIndex = index;
      return true;
    }

    final next = List.of(_before)
      ..add(context.snapPoint(context.worldPosition));
    _commit(next, 'Add waypoint');
    _target = null;
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final target = _target;
    if (target == null || _pointIndex < 0) return;

    // Written live so the path visibly follows the pointer; the undo entry is
    // recorded once on release.
    final points = List.of(binding.read(target));
    if (_pointIndex >= points.length) return;
    points[_pointIndex] = context.snapPoint(context.worldPosition);
    binding.write(target, points);
    sceneState.refresh();
  }

  @override
  void onPointerUp(ToolContext context) {
    final target = _target;
    if (target == null || _pointIndex < 0) {
      _reset();
      return;
    }

    _commit(List.of(binding.read(target)), 'Move waypoint');
    _reset();
  }

  @override
  void onCancel() {
    final target = _target;
    if (target != null && _before.isNotEmpty) {
      binding.write(target, List.of(_before));
    }
    _reset();
  }

  void _reset() {
    _target = null;
    _pointIndex = -1;
    _before = const [];
  }

  /// Records a waypoint change as one undoable command.
  ///
  /// Both sides hold their own copies: the component owns a mutable list, so
  /// storing a reference would leave undo and redo pointing at the same object.
  void _commit(List<Offset> next, String label) {
    final target = _target;
    if (target == null) return;

    final before = List<Offset>.of(_before);
    final after = List<Offset>.of(next);
    history.push(
      ComponentFieldCommand(
        label: label,
        component: target,
        write: (component, value) => binding.write(
          component,
          List<Offset>.of((value as List?)?.cast<Offset>() ?? const []),
        ),
        before: before,
        after: after,
        sceneState: sceneState,
      ),
    );
  }

  jge.Component? _selectedPathComponent() {
    final selected = sceneState.selectedEntity.value;
    if (selected == null || !selected.isAlive) return null;
    return binding.resolve(selected);
  }

  int _pointNear(jge.Component component, Offset point) {
    final points = binding.read(component);
    for (var i = 0; i < points.length; i++) {
      if ((points[i] - point).distance <= grabRadius) return i;
    }
    return -1;
  }
}
