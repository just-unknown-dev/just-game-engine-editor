import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../entities/scope_entities.dart';
import 'level_map_documents.dart';
import 'tile_commands.dart';
import 'package:just_editor_core/host.dart';
import 'scope_level_maps.dart';

/// Where the Level Designer puts what it places: under the scene's Level
/// Map, on the map's layer at the depth being placed at.
///
/// The layer being painted, when it draws at that depth; else the one drawn
/// frontmost there; else — made in the same undo step — a new layer named
/// after the depth. The map itself is made for the first thing placed in a
/// scene, in the same step too. Each thing placed is an entity of its own:
/// a child of the map, drawn and hidden with its layer.
abstract final class MapPlacement {
  /// The layer of [target] things placed at [depth] go on, or null when the
  /// map has none there and [place] would make one. [painted] is the layer
  /// being painted.
  static jge.MapLayerData? layerAt(
    LevelMapTarget target,
    String depth, {
    jge.MapLayerData? painted,
  }) {
    if (painted != null && painted.sortLayerId == depth) return painted;
    return target.data.layers.where((l) => l.sortLayerId == depth).lastOrNull;
  }

  /// What [place] would put something at [depth] on, in words: "Level Map ▸
  /// Ground", "Level Map ▸ a new Background layer", "a new Level Map".
  static String describe(EditorScope scope, jge.World world, String depth) {
    final target = scope.tiles.peek(world);
    if (target == null) {
      return jge.LevelMaps.primaryEntity(world) == null
          ? 'a new ${jge.LevelMaps.primaryName}'
          : jge.LevelMaps.primaryName;
    }
    final name = target.entity.name ?? jge.LevelMaps.primaryName;
    final layer = layerAt(
      target,
      depth,
      painted: scope.tiles.peekLayer(target),
    );
    return layer == null
        ? '$name ▸ a new ${_labelOf(scope, depth)} layer'
        : '$name ▸ ${layer.name}';
  }

  /// [components] made ready to go on [layer]: without parent links of
  /// their own — where they go decides those — and with a
  /// [jge.LayerComponent] naming the layer, added when they have none.
  static List<jge.Component> normalize(
    List<jge.Component> components,
    jge.MapLayerData layer,
  ) {
    final out = [
      for (final c in components)
        if (c is! jge.ParentComponent && c is! jge.ChildrenComponent) c,
    ];
    var lc = out.whereType<jge.LayerComponent>().firstOrNull;
    if (lc == null) {
      lc = jge.LayerComponent();
      out.add(lc);
    }
    lc
      ..mapLayer = layer.id
      ..layerId = layer.sortLayerId
      ..layer = layer.sortLayer
      ..zOrder = layer.zOrder;
    return out;
  }

  /// Makes an entity of each of [things] — a name, and components already
  /// placed in the world — under the scene's Level Map, on its layer at
  /// [depth], as one undo step called [label]. Selects the one made, when
  /// [select] and it is one. The entities, or null having said why through
  /// [say].
  static List<jge.Entity>? place(
    EditorScope scope,
    jge.World world,
    List<(String? name, List<jge.Component> components)> things, {
    required String depth,
    required String label,
    void Function(String message)? say,
    bool select = true,
  }) {
    if (things.isEmpty) return const [];
    final made = <jge.Entity>[];
    final placed = placeWith(
      scope,
      world,
      depth: depth,
      label: label,
      say: say,
      make: (mapName, onLayer) => CreateEntitiesCommand(
        label: label,
        world: world,
        sceneState: scope.sceneState,
        specs: [
          for (final (name, components) in things)
            EntitySpec(
              name: name,
              componentsJson: [
                for (final c in normalize(components, onLayer))
                  ?scope.codec.encode(c),
              ],
              codec: scope.codec,
              parentName: mapName,
            ),
        ],
        onCreated: (created) {
          made
            ..clear()
            ..addAll(created);
          if (select && created.length == 1) {
            scope.sceneState.selectEntity(created.single);
          }
        },
      )..redo(),
    );
    return placed ? List.of(made) : null;
  }

  /// An empty entity — a transform and nothing else — at [at] on the map's
  /// layer at [depth], selected, as one undo step: the Level Designer's
  /// "New entity here". Null having said why through [say].
  static jge.Entity? createAt(
    EditorScope scope,
    jge.World world,
    Offset at, {
    required String depth,
    void Function(String message)? say,
  }) {
    final name = scope.entities.uniqueName('entity');
    return place(
      scope,
      world,
      [
        (
          name,
          [jge.TransformComponent(position: jge.Vector3(at.dx, at.dy, 0))],
        ),
      ],
      depth: depth,
      label: 'Create $name',
      say: say,
    )?.firstOrNull;
  }

  /// The entity copied in the editor at [at] on the map's layer at [depth]
  /// — whatever layer it was copied from — selected, as one undo step: the
  /// Level Designer's "Paste here". Null with nothing copied, or having
  /// said why through [say].
  static jge.Entity? pasteAt(
    EditorScope scope,
    jge.World world,
    Offset at, {
    required String depth,
    void Function(String message)? say,
  }) {
    final copied = scope.sceneState.clipboard.value;
    if (copied == null || copied.isEmpty) return null;
    final components = [for (final json in copied) ?scope.codec.decode(json)];
    final t = components.whereType<jge.TransformComponent>().firstOrNull;
    if (t != null) {
      t.position.setValues(at.dx, at.dy, t.position.z);
    } else {
      components.insert(
        0,
        jge.TransformComponent(position: jge.Vector3(at.dx, at.dy, 0)),
      );
    }
    final name = scope.entities.uniqueName('entity');
    return place(
      scope,
      world,
      [(name, components)],
      depth: depth,
      label: 'Paste $name',
      say: say,
    )?.firstOrNull;
  }

  /// Puts what [make] makes under the scene's Level Map, on its layer at
  /// [depth], as one undo step called [label] — the map, and the layer,
  /// made for it in the same step when there are none.
  ///
  /// [make] is given the map's name (what is placed finds its parent by)
  /// and the layer, and returns the edit that made what is placed, done
  /// already — or null, having made nothing. False when nothing was
  /// placed, having said why through [say].
  static bool placeWith(
    EditorScope scope,
    jge.World world, {
    required String depth,
    required String label,
    required EditorCommand? Function(String mapName, jge.MapLayerData layer)
    make,
    void Function(String message)? say,
  }) {
    final provision = scope.mapProvision;
    final target = provision.ensure(world);
    if (target == null) {
      say?.call(whyNoMap(scope, world));
      return false;
    }
    final mapName = target.entity.name;
    if (target.isReadOnly || mapName == null) {
      provision.cancel();
      say?.call(
        mapName == null
            ? 'Name the map first: what is placed on it finds it by name'
            : '${target.path} is a Tiled map: convert it to place things '
                  'on it',
      );
      return false;
    }
    final existing = layerAt(
      target,
      depth,
      painted: scope.tiles.peekLayer(target),
    );
    if (existing != null && (existing.locked || !existing.visible)) {
      provision.cancel();
      say?.call(
        '${existing.name} is ${existing.locked ? 'locked' : 'hidden'}: '
        '${existing.locked ? 'unlock' : 'show'} it to place things on it',
      );
      return false;
    }

    var layer = existing;
    EditorCommand? structure;
    if (layer == null) {
      if (provision.isPending) {
        // Part of the map being made: its capture holds the layer.
        layer = _newLayer(scope, target.data, depth);
      } else {
        structure = MapStructureCommand.record(
          label: label,
          docs: scope.mapDocs,
          ref: target.ref,
          change: (map) => layer = _newLayer(scope, map, depth),
        );
      }
    }
    final onLayer = layer!;
    final create = make(mapName, onLayer);
    if (create == null) {
      // Nothing made: nor is the layer, nor the map, made for it.
      structure?.undo();
      provision.cancel();
      return false;
    }

    if (provision.isPending) {
      provision.keepWith(label, create);
    } else if (structure != null) {
      scope.history.pushApplied(
        CompositeCommand(label: label, commands: [structure, create]),
      );
    } else {
      scope.history.pushApplied(create);
    }
    scope.tiles.layerId.value = onLayer.id;
    scope.sceneState.markDirty();
    return true;
  }

  /// Why the scene's Level Map cannot be drawn on: there is none yet, its
  /// file could not be read — and why — or it is still loading.
  static String whyNoMap(EditorScope scope, jge.World world) {
    final entity = jge.LevelMaps.primaryEntity(world);
    if (entity == null) {
      return 'Nothing painted yet: the ${jge.LevelMaps.primaryName} is made '
          'when you first paint';
    }
    final component = entity.getComponent<jge.LevelMapComponent>();
    final path = component != null && component.usesFile
        ? component.mapPath.trim()
        : null;
    final failure = path == null ? null : scope.mapDocs.tiles.failureOf(path);
    if (failure != null) {
      return "The ${jge.LevelMaps.primaryName}'s file $path could not be "
          'read: $failure';
    }
    return 'The ${jge.LevelMaps.primaryName} is still loading';
  }

  static jge.MapLayerData _newLayer(
    EditorScope scope,
    jge.LevelMapData map,
    String depth,
  ) {
    final order =
        scope.layers.byId(depth)?.order ?? scope.layers.orderOf(depth);
    final base = _labelOf(scope, depth);
    final taken = {for (final l in map.layers) l.name};
    var name = base;
    for (var n = 2; taken.contains(name); n++) {
      name = '$base $n';
    }
    // Among the layers by depth: after every layer drawn at or behind it.
    var index = 0;
    for (var i = 0; i < map.layers.length; i++) {
      if (map.layers[i].sortLayer <= order) index = i + 1;
    }
    return map.addLayer(name: name, index: index)
      ..sortLayerId = depth
      ..sortLayer = order;
  }

  static String _labelOf(EditorScope scope, String depth) {
    final label = scope.layers.byId(depth)?.label;
    if (label != null && label.isNotEmpty) return label;
    return depth.isEmpty ? depth : depth[0].toUpperCase() + depth.substring(1);
  }
}
