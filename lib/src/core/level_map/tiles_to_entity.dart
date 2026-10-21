import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'level_map_documents.dart';
import 'tile_commands.dart';
import '../scope/editor_scope_services.dart';

/// Tiles cut out of a map layer into an entity of their own: a small map of
/// just those tiles, a child of the level's map on the layer they came from
/// — a piece of the map, to move about or give behaviour to.
///
/// The piece draws where the tiles were, and collides as they did.
abstract final class TilesToEntity {
  /// Moves the tiles in [cells] of [layer] of [target] into a new entity
  /// called after [name], as one undo step, and selects it. The entity, or
  /// null having said why through [say].
  static jge.Entity? cut(
    EditorScope scope,
    jge.World world,
    LevelMapTarget target,
    jge.MapLayerData layer,
    Set<jge.TileCoord> cells, {
    String name = 'Tiles',
    void Function(String message)? say,
  }) {
    final mapName = target.entity.name;
    if (target.isReadOnly) {
      say?.call('${target.path} is a Tiled map: convert it to edit it');
      return null;
    }
    if (mapName == null) {
      say?.call('Name the map first: its pieces find it by name');
      return null;
    }
    if (layer.locked) {
      say?.call('${layer.name} is locked');
      return null;
    }
    if (layer.parallaxX != 1 || layer.parallaxY != 1) {
      // A piece is placed by its own origin, not its layer's parallax: it
      // would drift from where its tiles were.
      say?.call('${layer.name} has parallax: its tiles cannot be cut out');
      return null;
    }
    final filled = [
      for (final c in cells)
        if (!jge.TileCell.isEmpty(layer.cells.cellAt(c.x, c.y))) c,
    ];
    if (filled.isEmpty) {
      say?.call('The selection holds no tiles');
      return null;
    }

    final data = target.data;
    final geometry = target.geometry;
    final (sx, sy) = _start(data, filled);
    final store = jge.TileChunkStore();
    for (final c in filled) {
      store.setCell(c.x - sx, c.y - sy, layer.cells.cellAt(c.x, c.y));
    }
    final piece =
        jge.LevelMapData(
            orientation: data.orientation,
            tileWidth: data.tileWidth,
            tileHeight: data.tileHeight,
            staggerAxis: data.staggerAxis,
            staggerIndex: data.staggerIndex,
            hexSideLength: data.hexSideLength,
            renderOrder: data.renderOrder,
            tilesets: [...data.tilesets],
            nextLayerId: 2,
          )
          ..layers.add(
            layer.copy(id: 1, cells: store)
              ..locked = false
              ..visible = true,
          );

    // Where the piece's cell (0, 0) must be for every tile to stay put.
    final p = target.entity.getComponent<jge.TransformComponent>()!.position;
    final at =
        Offset(p.x, p.y) +
        geometry.cellOrigin(sx, sy) -
        geometry.cellOrigin(0, 0);

    final label =
        'Make ${filled.length} tile${filled.length == 1 ? '' : 's'} '
        'an entity';
    final stroke = TileStroke(
      docs: scope.mapDocs,
      ref: target.ref,
      layer: layer,
    );
    for (final c in filled) {
      stroke.set(c, jge.TileCell.empty);
    }
    final cleared = stroke.finish(label);
    jge.Entity? made;
    final create = CreateEntitiesCommand(
      label: label,
      world: world,
      sceneState: scope.sceneState,
      specs: [
        EntitySpec(
          name: scope.entities.uniqueName(name),
          componentsJson: [
            for (final c in <jge.Component>[
              jge.TransformComponent(position: jge.Vector3(at.dx, at.dy, 0)),
              jge.LevelMapComponent(inline: piece),
              jge.LayerComponent(
                layerId: layer.sortLayerId,
                layer: layer.sortLayer,
                zOrder: layer.zOrder,
                mapLayer: layer.id,
              ),
            ])
              ?scope.codec.encode(c),
          ],
          codec: scope.codec,
          parentName: mapName,
        ),
      ],
      onCreated: (created) {
        made = created.firstOrNull;
        if (made != null) scope.sceneState.selectEntity(made!);
      },
    )..redo();
    scope.history.pushApplied(
      CompositeCommand(label: label, commands: [?cleared, create]),
    );
    scope.tiles.selection.value = const {};
    scope.sceneState.markDirty();
    say?.call('Made ${made?.name ?? 'an entity'} of ${filled.length} tiles');
    return made;
  }

  /// The cell the piece's (0, 0) is: the corner of [cells], moved back to
  /// an even row (or column) of a staggered or hexagonal map, whose cells
  /// sit differently in odd ones.
  static (int, int) _start(jge.LevelMapData map, List<jge.TileCoord> cells) {
    var sx = cells.first.x, sy = cells.first.y;
    for (final c in cells) {
      if (c.x < sx) sx = c.x;
      if (c.y < sy) sy = c.y;
    }
    final staggered =
        map.orientation == jge.MapOrientation.staggered ||
        map.orientation == jge.MapOrientation.hexagonal;
    if (staggered) {
      if (map.staggerAxis == jge.TileStaggerAxis.x) {
        sx -= sx & 1;
      } else {
        sy -= sy & 1;
      }
    }
    return (sx, sy);
  }
}
