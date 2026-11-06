part of 'just_game_editor_plugin.dart';

/// Files dropped on the viewport: what may be dropped, why not, and what a
/// drop makes — a sprite, a tileset's map, a map file, a module's asset.
extension PluginAssetDrops on JustGameEditorPlugin {
  /// Makes an entity for the asset at [path], where it was dropped on the
  /// viewport ([canvasPosition], in the canvas's own pixels): a still sprite
  /// for an image, a sprite animation for an atlas or a sprite project (whose
  /// atlas sits beside it). One undo step while the Level Designer is open.
  /// Null when there is no scene, or the file is not something to place.
  @internal
  Entity? dropAsset(String path, Offset canvasPosition) {
    if (!sceneState.hasScene ||
        !JustGameEditorPlugin.canDropAsset(
          path,
          mode: sceneState.editingMode,
          scope: scope,
        )) {
      return null;
    }
    final at = engine.camera.mainCamera.screenToWorld(canvasPosition);
    final view = scope.editorView;
    // In space a sprite stands where the pointer meets the ground; a model
    // on the surface under it.
    final ground = view.isPlanar ? null : view.screenToGround(canvasPosition);
    final surface = view.isPlanar ? null : surfaceAt(canvasPosition);
    // A kind a module knows makes what it makes.
    if (scope.assetKinds.of(path).drop case final drop?) {
      return drop(
        AssetDrop(
          scope: scope,
          path: path,
          at: surface?.position ?? Vector3(at.dx, at.dy, 0),
          mode: sceneState.editingMode,
          surface: surface,
          place: (components, name) => _place(path, components, name: name),
        ),
      );
    }
    final lower = path.toLowerCase();
    // What is dropped sits on the grid, as the Level Designer places it.
    final grid = sceneState.gridSize.value;
    double snap(double v) => grid > 0 ? (v / grid).round() * grid : v;
    final onGrid = Offset(snap(at.dx), snap(at.dy));
    if (lower.endsWith('.tileset.json')) return _dropTileset(path);
    if (LevelMapFiles.isMapFile(lower)) return _dropMapFile(path);
    if (TiledImporter.isTiledMap(path)) {
      unawaited(
        BuiltInTileContributions.importIntoScene(scope, path, at: onGrid),
      );
      return null;
    }
    final dot = path.lastIndexOf('.');
    final stem = path.substring(path.lastIndexOf('/') + 1, dot);
    final isImage = !lower.endsWith('.json') && !lower.endsWith('.jsprite');
    final components = <Component>[
      TransformComponent(position: ground ?? Vector3(at.dx, at.dy, 0)),
      if (isImage)
        SpriteComponent(spritePath: path, pixelArt: true)
      else
        SpriteAnimationComponent(
          atlasPath: lower.endsWith('.json')
              ? path
              : '${path.substring(0, dot)}.json',
        ),
    ];
    final session = designer.value;
    if (session != null) {
      // Designing a level: what is dropped goes under its map, on a layer
      // at the depth being placed at.
      final placed = MapPlacement.place(
        scope,
        engine.world,
        [(stem, components)],
        depth: session.controller.activeLayerId.value,
        label: 'Place $stem',
        say: (message) => logService.log(message, source: 'assets'),
      );
      if (placed == null || placed.isEmpty) return null;
      logService.log('Placed $stem from $path.', source: 'assets');
      return placed.single;
    }
    final entity = engine.world.createEntityWithComponents(
      components,
      name: stem,
    );
    sceneState
      ..markDirty()
      ..refresh()
      ..selectEntity(entity);
    history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: 'Place $stem',
        world: engine.world,
        sceneState: sceneState,
        entities: [entity],
        codec: scope.codec,
      ),
    );
    logService.log('Placed $stem from $path.', source: 'assets');
    return entity;
  }

  /// Places an entity of [components] — named after [path], as a dropped
  /// sprite is, unless [name] is given — selected, as one undo step.
  Entity _place(String path, List<Component> components, {String? name}) {
    final entity = engine.world.createEntityWithComponents(
      components,
      name: name ?? tiledStem(path),
    );
    sceneState
      ..markDirty()
      ..refresh()
      ..selectEntity(entity);
    history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: 'Place ${entity.name}',
        world: engine.world,
        sceneState: sceneState,
        entities: [entity],
        codec: scope.codec,
      ),
    );
    logService.log('Placed ${entity.name} from $path.', source: 'assets');
    return entity;
  }

  /// A tileset dropped: the map being painted gets it, and the Tileset
  /// panel shows it. With no map yet, the scene's Level Map is made to hold
  /// it, its cells the tileset's size.
  Entity? _dropTileset(String path) {
    final tiles = scope.tiles;
    final provision = scope.mapProvision;
    final tileSize = engine.context.tiles.loadedTileset(path)?.tileWidth;
    final target = provision.ensure(engine.world, tileSize: tileSize);
    if (target == null) {
      logService.log('The Level Map is still loading.', source: 'assets');
      return null;
    }
    if (target.isReadOnly) {
      logService.log(
        '${target.path} is a Tiled map: it cannot take another tileset.',
        source: 'assets',
      );
      return null;
    }
    var slot = target.data.slotOf(path);
    if (provision.isPending) {
      // One undo step: the map, and the tileset in it.
      slot = target.data.addTileset(path);
      provision.keep('Add tileset');
      logService.log(
        'Made the ${LevelMaps.primaryName} to paint ${tiledStem(path)} on.',
        source: 'assets',
      );
    } else if (slot < 0) {
      final command = MapStructureCommand.record(
        label: 'Add tileset',
        docs: scope.mapDocs,
        ref: target.ref,
        change: (map) => slot = map.addTileset(path),
      );
      if (command != null) history.pushApplied(command);
      logService.log(
        'Added ${tiledStem(path)} to ${target.entity.name}.',
        source: 'assets',
      );
    }
    tiles.slot.value = slot;
    return target.entity;
  }

  /// A map file dropped: it becomes the scene's Level Map — made for it, or
  /// the empty one switched to it. A map with something painted on it is
  /// kept, and the file is not used: a scene has one map.
  Entity? _dropMapFile(String path) {
    final existing = LevelMaps.primaryEntity(engine.world);
    if (existing == null) {
      final entity = _place(path, [
        TransformComponent(),
        LevelMapComponent(mapPath: path),
      ], name: LevelMaps.primaryName);
      scope.tiles.selectMap(entity);
      return entity;
    }
    final c = existing.getComponent<LevelMapComponent>()!;
    if (c.usesFile && c.mapPath.trim() == path) {
      scope.tiles.selectMap(existing);
      sceneState.selectEntity(existing);
      return existing;
    }
    final inline = c.usesFile ? null : c.inline;
    if (inline != null && LevelMapProvision.isBlank(inline)) {
      history.pushApplied(
        MapSourceCommand(
          label: 'Use ${tiledStem(path)}',
          docs: scope.mapDocs,
          entityId: existing.id,
          entityName: existing.name,
          before: (path: '', inline: inline.toJson()),
          after: (path: path, inline: null),
        )..redo(),
      );
      scope.tiles.selectMap(existing);
      sceneState.selectEntity(existing);
      logService.log('${existing.name} is $path now.', source: 'assets');
      return existing;
    }
    logService.log(
      'The scene already has a map, ${existing.name}, with something on it: '
      'a scene has one. $path was not used.',
      level: DebuggerLogLevel.warning,
      source: 'assets',
    );
    return null;
  }
}
