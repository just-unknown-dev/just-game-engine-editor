import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/level_designer/state/built_in_prefabs.dart';
import 'package:just_editor_core/host.dart';
import 'level_map_documents.dart';
import '../scope/editor_scope_services.dart';

/// The scene's one Level Map, made when something is first drawn on it.
///
/// A scene starts with none. The first tile painted — or tileset dropped —
/// makes it: [ensure] puts an empty one in the scene for the gesture to draw
/// on, and [commit] records its making and what was drawn as **one** undo
/// step, so one Ctrl+Z takes both away. A gesture that draws nothing leaves
/// no map behind.
class LevelMapProvision {
  LevelMapProvision(this.scope);

  final EditorScope scope;

  Entity? _made;
  World? _world;

  /// Whether a map [ensure] made is waiting for [commit].
  bool get isPending => _made != null;

  /// Whether [map] has nothing painted on it: what a dropped or imported map
  /// may take the place of.
  static bool isBlank(LevelMapData map) =>
      map.layers.every((l) => l.cells.usedBounds == null);

  /// The map to draw on: the one being painted, else the scene's Level Map,
  /// else — made now — a new, empty one at the origin with one layer,
  /// `Ground`, whose tiles collide; its cells [tileSize] square, the grid's
  /// by default. Null only while a map file is still loading.
  LevelMapTarget? ensure(World world, {int? tileSize}) {
    final tiles = scope.tiles;
    final current = tiles.target(world);
    if (current != null) return current;
    final existing = LevelMaps.primaryEntity(world);
    if (existing != null) {
      tiles.selectMap(existing);
      return scope.mapDocs.resolve(existing);
    }
    final grid = scope.sceneState.gridSize.value.round();
    final size = tileSize ?? (grid > 0 ? grid : 32);
    final entity = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: BuiltInPrefabs.newLevelMap(tileSize: size)),
    ], name: LevelMaps.primaryName);
    scope.sceneState.refresh();
    _made = entity;
    _world = world;
    tiles.selectMap(entity);
    return scope.mapDocs.resolve(entity);
  }

  /// Ends the gesture [ensure] was asked for. [edit] is what it did, as an
  /// undo step already applied, or null when it did nothing.
  ///
  /// With a map made for it, the making and [edit] become one undo step,
  /// [label] — or, when it drew nothing, the map is taken away again.
  /// Otherwise [edit] is recorded as it is.
  void commit(String label, EditorCommand? edit) {
    final made = _made;
    if (made == null || !made.isAlive) {
      _made = null;
      if (edit != null) scope.history.pushApplied(edit);
      return;
    }
    if (edit == null) {
      cancel();
    } else {
      keep(label);
    }
  }

  /// Keeps a map [ensure] made — as its own undo step, [label], with
  /// whatever was done to it since.
  void keep(String label) {
    final made = _made;
    final world = _world;
    _made = null;
    if (made == null || world == null || !made.isAlive) return;
    // Captured as it stands now, cells and all: a redo makes the map with
    // what was drawn on it.
    scope.history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: label,
        world: world,
        sceneState: scope.sceneState,
        entities: [made],
        codec: scope.codec,
        onCreated: (created) {
          if (created.isNotEmpty) scope.tiles.selectMap(created.first);
        },
      ),
    );
    scope.sceneState.markDirty();
  }

  /// Keeps a map [ensure] made together with [edit] — already applied — as
  /// one undo step, [label]: for what goes into the map's tree rather than
  /// its data, entities put on its layers. A redo makes the map first, and
  /// an undo takes [edit] back first. With no map made, [edit] is recorded
  /// as it is.
  void keepWith(String label, EditorCommand edit) {
    final made = _made;
    final world = _world;
    _made = null;
    if (made == null || world == null || !made.isAlive) {
      scope.history.pushApplied(edit);
      return;
    }
    scope.history.pushApplied(
      CompositeCommand(
        label: label,
        commands: [
          CreateEntitiesCommand.adopting(
            label: label,
            world: world,
            sceneState: scope.sceneState,
            entities: [made],
            codec: scope.codec,
            onCreated: (created) {
              if (created.isNotEmpty) scope.tiles.selectMap(created.first);
            },
          ),
          edit,
        ],
      ),
    );
    scope.sceneState.markDirty();
  }

  /// Takes away a map [ensure] made that nothing was drawn on.
  void cancel() {
    final made = _made;
    final world = _world;
    _made = null;
    if (made == null || world == null || !made.isAlive) return;
    scope.sceneState.removeEntityNode(made.id);
    world.destroyEntity(made);
    scope.sceneState.refresh();
  }
}
