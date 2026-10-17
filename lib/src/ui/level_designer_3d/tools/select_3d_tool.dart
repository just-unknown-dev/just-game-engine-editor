import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// The 3-D designer's Select: a click picks what is under the pointer and
/// the gizmo moves, turns and scales it — All, Move, Scale and Rotate (Q,
/// W, E, R) are its gizmos. A drag from empty space draws a marquee that
/// selects everything whose middle it holds; Shift or Ctrl adds to what is
/// selected.
///
/// It shares the 2-D Select's id, so those keys and every module that
/// switches back to Select find it in either mode. A press on something is
/// not its own: picking and the gizmo are the viewport's, which the 3-D
/// designer leaves working.
class Select3DTool extends LevelToolHandler {
  Offset? _from;
  bool _adding = false;

  /// Below this, in pixels, a drag is a click: on empty space, a click
  /// clears the selection.
  static const double clickSlop = 4;

  @override
  String get id => BuiltInTools.select;

  @override
  String get label => 'Select';

  @override
  IconData get icon => Icons.near_me;

  @override
  String? get description =>
      'Click to select; drag the gizmo to move, turn or scale (Q W E R); '
      'drag from empty space for a marquee (Shift adds)';

  @override
  int get order => 10;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space, at = context.screenPosition;
    if (space == null || at == null) return false;
    // Something under the pointer: picking it is the viewport's.
    if (space.surface().onto != null) return false;
    _from = at;
    _adding = context.isShiftDown || context.isCtrlDown;
    context.controller.screenRect.value = Rect.fromPoints(at, at);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final from = _from, at = context.screenPosition;
    if (from == null || at == null) return;
    context.controller.screenRect.value = Rect.fromPoints(from, at);
  }

  @override
  void onPointerUp(ToolContext context) {
    final from = _from;
    _from = null;
    final controller = context.controller;
    final rect = controller.screenRect.value;
    controller.screenRect.value = null;
    final view = context.camera;
    if (from == null || rect == null || view == null) return;
    final state = controller.sceneState;
    if (rect.longestSide < clickSlop) {
      if (!_adding) state.clearSelection();
      return;
    }
    final picked = RayEntityPicker().pickInRect(view, rect, [
      for (final e in context.world.query([jge.TransformComponent]))
        if (e.isActive && controller.isPickable(e)) e,
    ]);
    if (!_adding) state.clearSelection();
    for (final e in picked) {
      if (state.selectedEntity.value?.id == e.id ||
          state.isInMultiSelection(e.id)) {
        continue;
      }
      state.toggleMultiSelect(e);
    }
    controller.setStatus(
      picked.isEmpty ? 'Nothing in the marquee' : 'Selected ${picked.length}',
    );
  }

  @override
  void onCancel() => _from = null;
}
