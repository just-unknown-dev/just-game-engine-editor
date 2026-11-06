import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../designer_controls.dart';
import '../../../entities/scope_entities.dart';
import '../../../level_map/map_placement.dart';
import '../../../prefabs/scope_prefabs.dart';

/// Drag out a rectangle to place the active prefab, sized to the drag.
///
/// The fastest way to block out a level: the size *is* the gesture, so there
/// is no place-then-resize round trip through the inspector for every
/// platform.
class DrawRectTool extends LevelToolHandler {
  DrawRectTool({
    required this.sceneState,
    required this.history,
    required this.uniqueName,
    required this.codec,
    this.scope,
  });

  /// The editor, whose Level Map what is placed goes under — on the layer
  /// at the depth being placed at; without it, an entity of its own.
  final EditorScope? scope;

  /// Encodes and decodes components; the scope's codec.
  final SceneCodec codec;

  /// Shared selection and dirty state.
  final EditorSceneState sceneState;

  /// Where the create command is recorded.
  final EditorHistory history;

  /// Produces a unique entity name from a prefix, so two platforms never
  /// collide — the scene format re-links parents by name on load.
  final String Function(String prefix) uniqueName;

  @override
  String get id => BuiltInTools.draw;

  @override
  String get label => 'Draw';

  @override
  IconData get icon => Icons.add_box_outlined;

  @override
  String? get shortcut => 'B';

  @override
  String? get description =>
      'Drag out a rectangle to place the active prefab, sized to the drag';

  @override
  int get order => 20;

  @override
  String get group => ToolGroups.shapes;

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ActivePrefabChip(controller: options.controller),
      const SizedBox(width: 6),
      PlacementChip(options: options),
    ],
  );

  Offset? _start;

  @override
  bool onPointerDown(ToolContext context) {
    final prefab = context.controller.activePrefab;
    if (prefab == null) return false;

    _start = context.snapPoint(context.worldPosition);

    // Point prefabs place on release with their own size, so there is no
    // rectangle to preview while dragging.
    if (prefab.placement == PrefabPlacement.point) return true;

    context.controller.dragRect.value = Rect.fromPoints(_start!, _start!);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final start = _start;
    if (start == null) return;

    final prefab = context.controller.activePrefab;
    if (prefab == null || prefab.placement == PrefabPlacement.point) return;

    final current = context.snapPoint(context.worldPosition);
    final rect = DesignerGeometry.rectFromDrag(start, current);
    context.controller
      ..dragRect.value = rect
      ..setStatus('${rect.width.round()} x ${rect.height.round()}');
  }

  @override
  void onPointerUp(ToolContext context) {
    final start = _start;
    _start = null;
    final prefab = context.controller.activePrefab;
    context.controller.dragRect.value = null;
    if (start == null || prefab == null) return;

    final Rect placement;
    if (prefab.placement == PrefabPlacement.point) {
      final center = context.snapping
          ? DesignerGeometry.snapCenterForSize(
              context.worldPosition,
              prefab.defaultSize,
              context.gridSize,
            )
          : context.worldPosition;
      placement = Rect.fromCenter(
        center: center,
        width: prefab.defaultSize.width,
        height: prefab.defaultSize.height,
      );
    } else {
      var rect = DesignerGeometry.rectFromDrag(
        start,
        context.snapPoint(context.worldPosition),
      );
      // A click rather than a drag: fall back to the prefab's own size, so a
      // mis-click places something usable instead of a degenerate sliver.
      if (rect.width < context.gridSize / 2 ||
          rect.height < context.gridSize / 2) {
        rect = Rect.fromCenter(
          center: rect.center,
          width: prefab.defaultSize.width,
          height: prefab.defaultSize.height,
        );
      }
      placement = rect;
    }

    _place(context, prefab, placement);
  }

  @override
  void onCancel() {
    _start = null;
  }

  void _place(ToolContext context, PrefabDefinition prefab, Rect rect) {
    final scope = this.scope;
    // An instance of a prefab file: its entities, under the Level Map on
    // the layer at this depth, as anything placed is.
    if (prefab.instanceOf case final path? when scope != null) {
      _placeInstance(context, scope, prefab, path, rect.center);
      return;
    }
    final components = prefab.build(rect.center, rect.size);
    if (scope != null) {
      // Into the level's map: a child of it, on a layer at this depth.
      MapPlacement.place(
        scope,
        context.world,
        [(uniqueName(prefab.namePrefix ?? prefab.id), components)],
        depth: prefab.depth ?? context.controller.activeLayerId.value,
        label: 'Place ${prefab.name}',
        say: context.controller.setStatus,
      );
      return;
    }

    // Stamp the designer's active layer onto whatever the prefab produced, so
    // "draw on the background layer" actually works without every prefab
    // having to know about layers.
    final layerId = context.controller.activeLayerId.value;
    for (final component in components) {
      if (component is jge.LayerComponent) component.layerId = layerId;
    }

    final spec = EntitySpec(
      codec: codec,
      name: uniqueName(prefab.namePrefix ?? prefab.id),
      componentsJson: [for (final component in components) ?_encode(component)],
    );

    history.push(
      CreateEntitiesCommand(
        label: 'Place ${prefab.name}',
        world: context.world,
        sceneState: sceneState,
        specs: [spec],
        onCreated: (created) {
          if (created.isNotEmpty) sceneState.selectEntity(created.first);
        },
      ),
    );
  }

  /// Places an instance of the prefab file at [path] with its top at [at]:
  /// under the scene's Level Map, on its layer at the depth being placed
  /// at — the map and the layer made for it when there are none — selected,
  /// as one undo step.
  void _placeInstance(
    ToolContext context,
    EditorScope scope,
    PrefabDefinition prefab,
    String path,
    Offset at,
  ) {
    final instances = scope.prefabInstances;
    final file = instances.library.loaded(path);
    if (file == null) {
      context.controller.setStatus('The prefab $path is not read yet');
      return;
    }
    final world = context.world;
    final label = 'Place ${file.name}';
    String? placed;
    MapPlacement.placeWith(
      scope,
      world,
      depth: prefab.depth ?? context.controller.activeLayerId.value,
      label: label,
      say: context.controller.setStatus,
      make: (mapName, layer) {
        final entry = instances.entryFor(
          path,
          name: scope.entities.uniqueName(file.name),
          at: jge.Vector3(at.dx, at.dy, 0),
        );
        var made = <jge.Entity>[];
        final command = CallbackCommand(
          label: label,
          onRedo: () {
            final map = world.findEntityByName(mapName);
            made = instances.build([entry], under: map);
            final top = made.firstOrNull;
            if (top == null) return;
            // Its top on the layer, as [MapPlacement.normalize] puts
            // anything placed — drawn, hidden and counted with the layer:
            // its own layer component, or one added.
            final own = top.getComponent<jge.LayerComponent>();
            final onLayer = MapPlacement.normalize([?own], layer).single;
            if (own == null) top.addComponent(onLayer);
            sceneState.selectEntity(top);
          },
          onUndo: () {
            // Children before parents, none left pointing at one gone.
            for (final e in made.reversed) {
              if (!e.isAlive) continue;
              detachEntity(e, world: world, sceneState: sceneState);
              sceneState.removeEntityNode(e.id);
              world.destroyEntity(e);
            }
            made = const [];
            sceneState
              ..clearSelection()
              ..markDirty()
              ..refresh();
          },
        )..redo();
        if (made.isEmpty) return null;
        placed = made.first.name;
        return command;
      },
    );
    if (placed != null) {
      context.controller.setStatus('Placed $placed');
    }
  }

  /// Components are stored as JSON rather than live instances because
  /// [CreateEntitiesCommand] has to rebuild them after an undo has destroyed
  /// the originals.
  Map<String, dynamic>? _encode(jge.Component component) =>
      codec.encode(component);
}
