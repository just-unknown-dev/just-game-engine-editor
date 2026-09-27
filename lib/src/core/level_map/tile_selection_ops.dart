import 'package:just_game_engine/just_game_engine.dart';

import '../scope/editor_scope.dart';
import 'level_map_documents.dart';
import 'tile_commands.dart';
import 'tiles_to_entity.dart';

/// What can be done with the tiles selected with Select tiles, wherever it
/// is asked for: the tool's keys and options, the viewport's right-click
/// menu, the inspector.
///
/// The selection is of the layer being painted. Each change is one undo
/// step; [say] is told what happened, or why nothing did.
abstract final class TileSelectionOps {
  /// How many cells are selected.
  static int count(EditorScope scope) => scope.tiles.selection.value.length;

  /// The layer the selection is of — the one being painted — without
  /// choosing one; null when there is no map.
  static MapLayerData? layerOf(EditorScope scope, World world) {
    final target = scope.tiles.peek(world);
    return target == null ? null : scope.tiles.peekLayer(target);
  }

  /// How many of the selected cells hold a tile: what would become an
  /// entity, or be copied.
  static int tileCount(EditorScope scope, World world) {
    final layer = layerOf(scope, world);
    if (layer == null) return 0;
    return scope.tiles.selection.value
        .where((c) => !TileCell.isEmpty(layer.cells.cellAt(c.x, c.y)))
        .length;
  }

  /// The map and layer the selection is of, or null having said why.
  static ({LevelMapTarget target, MapLayerData layer})? _aim(
    EditorScope scope,
    World world,
    void Function(String message) say, {
    bool forEdit = true,
  }) {
    final tiles = scope.tiles;
    final target = tiles.target(world);
    final layer = target == null ? null : tiles.layerOf(target);
    if (target == null || layer == null) {
      say('No map to take tiles from');
      return null;
    }
    if (forEdit && target.isReadOnly) {
      say('${target.path} is a Tiled map: convert it to edit it');
      return null;
    }
    if (forEdit && layer.locked) {
      say('${layer.name} is locked');
      return null;
    }
    return (target: target, layer: layer);
  }

  /// Cuts the selected tiles out into an entity of their own, on their
  /// layer — see [TilesToEntity]. The entity, or null.
  static Entity? makeEntity(
    EditorScope scope,
    World world,
    void Function(String message) say,
  ) {
    final selected = scope.tiles.selection.value;
    if (selected.isEmpty) {
      say('Select some tiles first');
      return null;
    }
    final a = _aim(scope, world, say, forEdit: false);
    if (a == null) return null;
    return TilesToEntity.cut(
      scope,
      world,
      a.target,
      a.layer,
      selected,
      say: say,
    );
  }

  /// Copies the selected tiles, for Ctrl+V to paint. Whether there were
  /// any.
  static bool copy(
    EditorScope scope,
    World world,
    void Function(String message) say,
  ) {
    final selected = scope.tiles.selection.value;
    if (selected.isEmpty) {
      say('Select some tiles first');
      return false;
    }
    final a = _aim(scope, world, say, forEdit: false);
    if (a == null) return false;
    final stamp = TileStamp.capture(
      a.layer.cells,
      selected,
      a.target.geometry,
      skipEmpty: true,
    );
    if (stamp.isEmpty) {
      say('The selection holds no tiles');
      return false;
    }
    scope.tiles.clipboard = stamp;
    final n = stamp.cells.length;
    say('Copied $n tile${n == 1 ? '' : 's'}: Ctrl+V to paint them');
    return true;
  }

  /// Empties the selected cells, as one step called [label].
  static void delete(
    EditorScope scope,
    World world,
    void Function(String message) say, {
    String label = 'Delete tiles',
  }) {
    final selected = scope.tiles.selection.value;
    if (selected.isEmpty) {
      say('No tiles selected');
      return;
    }
    final a = _aim(scope, world, say);
    if (a == null) return;
    final stroke = TileStroke(
      docs: scope.mapDocs,
      ref: a.target.ref,
      layer: a.layer,
    );
    for (final cell in selected) {
      stroke.set(cell, TileCell.empty);
    }
    final command = stroke.finish(label);
    if (command != null) scope.history.pushApplied(command);
  }

  /// Copies the selected tiles, then empties their cells.
  static void cut(
    EditorScope scope,
    World world,
    void Function(String message) say,
  ) {
    if (copy(scope, world, say)) {
      delete(scope, world, say, label: 'Cut tiles');
    }
  }

  /// Lets go of the selection.
  static void deselect(EditorScope scope, void Function(String message) say) {
    scope.tiles.selection.value = const {};
    say('No tiles selected');
  }
}
