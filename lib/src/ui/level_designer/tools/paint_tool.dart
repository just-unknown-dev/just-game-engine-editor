import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/serialization/scene_codec.dart';
import '../../../core/state/editor_scene_state.dart';
import '../state/designer_geometry.dart';
import '../state/editor_commands.dart';
import '../state/level_designer_controller.dart';
import '../state/editor_history.dart';
import 'level_tool.dart';
import 'tool_registry.dart';

/// Paints prefabs onto the grid: brush, eraser, and rectangle fill.
///
/// The whole stroke commits as **one** undoable command, and the painted cells
/// are merged into as few rectangles as possible before any entity is created.
/// Without the merge, a modest painted area becomes hundreds of entities and
/// hundreds of static physics bodies — a per-frame broad-phase cost and a
/// scene tree nobody can read.
class PaintTool extends LevelToolHandler {
  PaintTool({
    required this.sceneState,
    required this.history,
    required this.uniqueName,
    required this.codec,
  });

  /// Shared selection and dirty state.
  /// Encodes and decodes components; the scope's codec.
  final SceneCodec codec;
  final EditorSceneState sceneState;

  /// Where the stroke is recorded.
  final EditorHistory history;

  /// Produces unique entity names for the merged rectangles.
  final String Function(String prefix) uniqueName;

  @override
  String get id => BuiltInTools.paint;

  @override
  String get label => 'Paint';

  @override
  IconData get icon => Icons.brush;

  @override
  String? get shortcut => 'P';

  @override
  String? get description => 'Brush, rectangle fill and eraser on the grid';

  @override
  int get order => 30;

  final Set<Point2> _stroke = {};
  Offset? _rectStart;

  @override
  bool onPointerDown(ToolContext context) {
    final mode = context.controller.paintMode.value;

    if (mode == PaintMode.fill) {
      _stroke
        ..clear()
        ..addAll(_fillAt(context));
      return true;
    }

    if (mode == PaintMode.rectangle) {
      _rectStart = context.worldPosition;
      context.controller.dragRect.value = Rect.fromPoints(
        context.worldPosition,
        context.worldPosition,
      );
      return true;
    }

    _stroke.clear();
    _paintAt(context);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final mode = context.controller.paintMode.value;
    if (mode == PaintMode.fill) return;

    if (mode == PaintMode.rectangle) {
      final start = _rectStart;
      if (start == null) return;
      final rect = DesignerGeometry.rectFromDrag(start, context.worldPosition);
      context.controller
        ..dragRect.value = rect
        ..setStatus(
          '${(rect.width / context.gridSize).ceil()} x '
          '${(rect.height / context.gridSize).ceil()} cells',
        );
      return;
    }

    _paintAt(context);
  }

  @override
  void onPointerUp(ToolContext context) {
    final mode = context.controller.paintMode.value;

    if (mode == PaintMode.rectangle) {
      final start = _rectStart;
      _rectStart = null;
      context.controller.dragRect.value = null;
      if (start == null) return;
      final rect = DesignerGeometry.rectFromDrag(start, context.worldPosition);
      _stroke
        ..clear()
        ..addAll(context.grid.cellsIn(rect, context.gridSize));
    }

    if (_stroke.isEmpty) return;

    if (mode == PaintMode.eraser) {
      _commitErase(context);
    } else {
      _commitPaint(context);
    }
    _stroke.clear();
  }

  @override
  void onCancel() {
    _stroke.clear();
    _rectStart = null;
  }

  /// Records the cell under the pointer. Painting is deferred to release so
  /// the whole stroke merges and undoes as one action.
  void _paintAt(ToolContext context) {
    final grid = context.grid;
    _stroke.addAll(
      grid.brush(
        grid.cellAt(context.worldPosition, context.gridSize),
        context.controller.brushSize.value,
      ),
    );
    context.controller.setStatus('${_stroke.length} cells');
  }

  /// The empty region under the pointer, bounded by existing geometry.
  ///
  /// Walls are every visible entity's bounds; the fill is confined to the
  /// space the level already occupies, so an open region reports itself
  /// instead of filling to the edge of the world.
  Set<Point2> _fillAt(ToolContext context) {
    final cell = context.gridSize;
    final solids = [
      for (final e in context.world.query([jge.TransformComponent]))
        if (e.isActive && context.controller.isShownInViewport(e))
          ?DesignerGeometry.worldBounds(e),
    ];
    if (solids.isEmpty) {
      context.controller.setStatus('Nothing to fill against');
      return const {};
    }
    final extent = solids.reduce((a, b) => a.expandToInclude(b));
    final grid = context.grid;
    final blocked = <Point2>{
      // Deflated a hair so a wall that ends exactly on a grid line does not
      // claim the next cell over.
      for (final r in solids) ...grid.cellsIn(r.deflate(0.01), cell),
    };
    final result = grid.floodFill(
      grid.cellAt(context.worldPosition, cell),
      blocked,
      limit: grid.cellRange(extent, cell),
    );
    if (result == null) {
      context.controller.setStatus(
        'That region is open — close it off before filling',
      );
      return const {};
    }
    return result;
  }

  void _commitPaint(ToolContext context) {
    final prefab = context.controller.activePrefab;
    if (prefab == null) return;

    // As few entities as the cells allow: squares merge into rectangles;
    // cells that cannot merge become one entity each, at their bounds.
    final grid = context.grid;
    final merged =
        grid.merge(_stroke, context.gridSize) ??
        [for (final c in _stroke) grid.cellBounds(c, context.gridSize)];
    final layerId = context.controller.activeLayerId.value;
    final specs = <EntitySpec>[];

    for (final worldRect in merged) {
      final components = prefab.build(worldRect.center, worldRect.size);
      for (final component in components) {
        if (component is jge.LayerComponent) component.layerId = layerId;
      }

      specs.add(
        EntitySpec(
          name: uniqueName(prefab.namePrefix ?? prefab.id),
          componentsJson: [
            for (final component in components) ?codec.encode(component),
          ],
          codec: codec,
        ),
      );
    }

    if (specs.isEmpty) return;

    history.push(
      CreateEntitiesCommand(
        label: 'Paint ${prefab.name} (${specs.length})',
        world: context.world,
        sceneState: sceneState,
        specs: specs,
      ),
    );
    context.controller.setStatus(
      'Painted ${_stroke.length} cells as ${specs.length} entities',
    );
  }

  void _commitErase(ToolContext context) {
    final cellSize = context.gridSize;
    final doomed = <jge.Entity>{};

    for (final cell in _stroke) {
      final cellRect = context.grid.cellBounds(cell, cellSize);
      doomed.addAll(
        DesignerGeometry.entitiesIn(
          cellRect,
          context.world.query([jge.TransformComponent]),
          pickable: context.controller.isPickable,
        ),
      );
    }

    if (doomed.isEmpty) return;

    history.push(
      DeleteEntitiesCommand(
        label: 'Erase ${doomed.length} entities',
        world: context.world,
        sceneState: sceneState,
        entities: doomed.toList(),
        codec: codec,
      ),
    );
  }
}
