import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/graphics_3d.dart' show MaterialSlots;

import 'package:just_editor_core/host.dart';

/// The 3-D designer's Paint material: a click draws the shape or model
/// under the pointer with the material in hand (chosen in MATERIALS); a
/// drag paints everything it passes over, as one undo step. Alt+click
/// picks a thing's material up instead.
class MaterialPaint3DTool extends LevelToolHandler {
  /// A tool painting in [scope], with the material its 3-D state holds.
  MaterialPaint3DTool({required this.scope});

  /// The editor.
  final EditorScope scope;

  /// Its id.
  static const String toolId = 'materialPaint';

  ComponentEdit? _edit;
  final Set<jge.EntityId> _painted = {};

  @override
  String get id => toolId;

  @override
  String get label => 'Paint material';

  @override
  IconData get icon => Icons.format_paint_outlined;

  @override
  String? get shortcut => 'P';

  @override
  String? get description =>
      'Click a shape or model to draw it with the material in hand '
      '(MATERIALS); drag across several; Alt+click to pick one up';

  @override
  int get order => 30;

  @override
  String get group => ToolGroups.shapes;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  /// What the pointer is over: something drawn and not locked.
  jge.Entity? _under(ToolContext context) {
    final onto = context.space?.surface().onto;
    if (onto == null || !context.controller.isPickable(onto)) return null;
    return onto;
  }

  @override
  bool onPointerDown(ToolContext context) {
    if (context.space == null) return false;
    final state = scope.designer3D;
    final under = _under(context);
    if (context.isAltDown) {
      final path = under == null ? '' : MaterialSlots.materialOf(under);
      if (path.isEmpty) {
        context.controller.setStatus('No material file on that to pick up');
      } else {
        state.materialInHand.value = path;
        context.controller.setStatus('In hand: ${_name(path)}');
      }
      return true;
    }
    if (state.materialInHand.value == null) {
      context.controller.setStatus('Choose a material in MATERIALS');
      return true;
    }
    _painted.clear();
    _edit = null;
    _paint(under);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    if (_edit == null && _painted.isEmpty && scope.designer3D.materialInHand.value == null) {
      return;
    }
    _paint(_under(context));
  }

  @override
  void onPointerUp(ToolContext context) {
    final edit = _edit;
    final count = _painted.length;
    _edit = null;
    _painted.clear();
    if (edit == null) return;
    final path = scope.designer3D.materialInHand.value ?? '';
    if (edit.commit(count == 1 ? 'Paint ${_name(path)}' : 'Paint $count × ${_name(path)}')) {
      context.controller.setStatus('Painted $count with ${_name(path)}');
    }
  }

  @override
  void onCancel() {
    // What a stroke painted stays, as one step.
    final edit = _edit;
    _edit = null;
    _painted.clear();
    edit?.commit('Paint material');
  }

  void _paint(jge.Entity? entity) {
    final path = scope.designer3D.materialInHand.value;
    if (entity == null || path == null || !_painted.add(entity.id)) return;
    final holder = MaterialSlots.holderOf(entity);
    if (holder == null || MaterialSlots.materialOf(entity) == path) return;
    final edit = _edit ??= ComponentEdit.beginAll(scope, const []);
    edit.include(holder);
    MaterialSlots.assign(entity, path);
    scope.sceneState.refresh();
  }

  static String _name(String path) {
    final file = path.substring(path.lastIndexOf('/') + 1);
    return file.toLowerCase().endsWith('.material.json')
        ? file.substring(0, file.length - '.material.json'.length)
        : file;
  }
}
