import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../controls/designer_controls.dart';
import '../state/map_placement.dart';

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
    this.scope,
  });

  /// The editor, whose Level Map what is painted goes under — on the layer
  /// at the depth being painted at; without it, entities of their own.
  final EditorScope? scope;

  /// Encodes and decodes components; the scope's codec.
  final SceneCodec codec;

  /// Shared selection and dirty state.
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
  IconData get icon => Icons.format_paint;

  @override
  String? get shortcut => 'P';

  @override
  String? get description => 'Brush, rectangle fill and eraser on the grid';

  @override
  int get order => 30;

  @override
  String get group => ToolGroups.shapes;

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) {
    final controller = options.controller;
    return SignalBuilder<PaintMode>(
      signal: controller.paintMode,
      builder: (context, mode, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActivePrefabChip(controller: controller),
          const SizedBox(width: 6),
          PlacementChip(options: options),
          const OptionsDivider(),
          ChoicePicker<PaintMode>(
            signal: controller.paintMode,
            options: const [
              ToolChoice(
                value: PaintMode.brush,
                icon: Icons.brush,
                label: 'Brush',
              ),
              ToolChoice(
                value: PaintMode.rectangle,
                icon: Icons.crop_square,
                label: 'Rect',
              ),
              ToolChoice(
                value: PaintMode.eraser,
                icon: Icons.cleaning_services,
                label: 'Erase',
              ),
              ToolChoice(
                value: PaintMode.fill,
                icon: Icons.format_color_fill,
                label: 'Fill',
                tooltip: 'Fill the enclosed empty region you click',
              ),
            ],
          ),
          // Brush width only affects the brush and the eraser.
          if (mode == PaintMode.brush || mode == PaintMode.eraser) ...[
            const OptionsDivider(),
            const OptionsLabel('Size'),
            BrushSizePicker(signal: controller.brushSize),
          ],
        ],
      ),
    );
  }

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

  /// Past this many cells of wall, a fill is refused rather than laid out:
  /// a wall far bigger than any room would take seconds to grid.
  static const int maxWallCells = 250000;

  /// The empty region under the pointer, bounded by existing geometry.
  ///
  /// Walls are the bounds of every visible entity but those the click is
  /// inside: a camera's bounds, a region or a trigger drawn round the
  /// level contains the room being filled rather than walling it. A solid
  /// the click is inside is no room at all, and says so. The fill is
  /// confined to the space the walls occupy, so an open region reports
  /// itself instead of filling to the edge of the world.
  Set<Point2> _fillAt(ToolContext context) {
    final cell = context.gridSize;
    final at = context.worldPosition;
    final solids = <Rect>[];
    for (final e in context.world.query([jge.TransformComponent])) {
      if (!e.isActive || !context.controller.isShownInViewport(e)) continue;
      final bounds = DesignerGeometry.worldBounds(e);
      if (bounds == null) continue;
      if (bounds.contains(at)) {
        if (_isSolid(e)) {
          context.controller.setStatus(
            'The click is inside ${e.name ?? 'something solid'}: click the '
            'empty space to fill',
          );
          return const {};
        }
        continue;
      }
      solids.add(bounds);
    }
    if (solids.isEmpty) {
      context.controller.setStatus('Nothing to fill against');
      return const {};
    }
    final extent = solids.reduce((a, b) => a.expandToInclude(b));
    final grid = context.grid;
    // Deflated a hair so a wall that ends exactly on a grid line does not
    // claim the next cell over.
    final walls = [for (final r in solids) r.deflate(0.01)];
    var wallCells = 0.0;
    for (final r in walls) {
      final range = grid.cellRange(r, cell);
      wallCells += range.width * range.height;
    }
    if (wallCells > maxWallCells) {
      context.controller.setStatus(
        'The level is too big to fill at this grid size: use a larger '
        'grid, or Rect',
      );
      return const {};
    }
    final blocked = <Point2>{for (final r in walls) ...grid.cellsIn(r, cell)};
    final result = grid.floodFill(
      grid.cellAt(at, cell),
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

  /// Whether [entity] blocks movement: a collider on a body that is not a
  /// sensor. What a fill cannot start inside.
  static bool _isSolid(jge.Entity entity) =>
      entity.hasComponent<jge.Collider2D>() &&
      !(entity.getComponent<jge.RigidBody2D>()?.isSensor ?? false);

  void _commitPaint(ToolContext context) {
    final prefab = context.controller.activePrefab;
    if (prefab == null) return;
    if (prefab.instanceOf != null) {
      // A prefab file places an instance of itself, at its own size: it
      // builds nothing to stretch over the painted cells.
      context.controller.setStatus(
        '${prefab.name} is a prefab file: place it with Draw (B). Paint '
        'paints shapes',
      );
      return;
    }

    // As few entities as the cells allow: squares merge into rectangles;
    // cells that cannot merge become one entity each, at their bounds.
    final grid = context.grid;
    final merged =
        grid.merge(_stroke, context.gridSize) ??
        [for (final c in _stroke) grid.cellBounds(c, context.gridSize)];
    final layerId = context.controller.activeLayerId.value;
    final scope = this.scope;
    if (scope != null) {
      final things = [
        for (final worldRect in merged)
          // A copy: what a prefab returns is never changed in place.
          if ([...prefab.build(worldRect.center, worldRect.size)]
              case final components when components.isNotEmpty)
            (uniqueName(prefab.namePrefix ?? prefab.id), components),
      ];
      if (things.isEmpty) {
        context.controller.setStatus('${prefab.name} builds nothing to paint');
        return;
      }
      // Into the level's map: children of it, on a layer at this depth.
      final placed = MapPlacement.place(
        scope,
        context.world,
        things,
        depth: prefab.depth ?? layerId,
        label: 'Paint ${prefab.name} (${merged.length})',
        say: context.controller.setStatus,
        select: false,
      );
      if (placed != null) {
        context.controller.setStatus(
          'Painted ${_stroke.length} cells as ${placed.length} entities',
        );
      }
      return;
    }
    final specs = <EntitySpec>[];

    for (final worldRect in merged) {
      final components = prefab.build(worldRect.center, worldRect.size);
      if (components.isEmpty) continue;
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
    // The map itself is not erased with what is on it.
    doomed.removeWhere((e) => e.hasComponent<jge.LevelMapComponent>());
    // What a module protects stays, and the log says so.
    final erased = scope?.deletable(doomed) ?? doomed.toList();

    if (erased.isEmpty) return;
    history.push(
      DeleteEntitiesCommand(
        label: 'Erase ${erased.length} entities',
        world: context.world,
        sceneState: sceneState,
        entities: erased,
        codec: codec,
      ),
    );
  }
}
