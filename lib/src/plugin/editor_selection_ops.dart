part of 'just_game_editor_plugin.dart';

/// What the viewport does to the selection: framing it, dropping it to the
/// ground, arrays, placing prefabs in space, deleting and duplicating.
extension PluginSelection on JustGameEditorPlugin {
  // ── Level Designer selection operations ───────────────────────────────────
  //
  // Thin on purpose: the designer session calls these, and each needs the
  // session's own history to be one undo step.

  /// Entities covered by the current selection.
  @internal
  List<Entity> get selectionEntities => entities.selectionEntities;

  /// Puts the viewport on [entity] — what double-clicking a row in the
  /// scene tree does.
  ///
  @internal
  void focusOn(Entity entity) {
    if (entity.hasComponent<LevelMapComponent>()) {
      designLevelMap(entity);
      return;
    }
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) {
      sceneState.selectEntity(entity);
      return;
    }
    if (scope.editorView case final OrbitFlyEditorView view) {
      // In space: around it, far enough back to see all of it.
      final box = Aabb3();
      if (RayEntityPicker.boundsOf(entity, box)) view.focusOn(box);
      sceneState.selectEntity(entity);
      return;
    }
    engine.camera.mainCamera.position = Offset(
      transform.position.x,
      transform.position.y,
    );
    sceneState.selectEntity(entity);
  }

  /// In 3-D: the surface under [canvasPosition] — the nearest drawn
  /// entity's, by its real shape where a pick test knows it, else the
  /// working plane, else the ground — where something placed there goes.
  @internal
  SurfacePoint surfaceAt(Offset canvasPosition) {
    final view = scope.editorView;
    final found = RayEntityPicker(
      tests: () => scope.pickTests,
    ).placementAt(view, canvasPosition, engine.world.entities.where(_isDrawn));
    if (found.onto != null) return found;
    final plane = workingPlane3D;
    final hit = plane.intersect(view.screenToRay(canvasPosition));
    return hit == null ? found : SurfacePoint(hit, plane.normal);
  }

  /// The 3-D designer's working plane: as set, or through the base of the
  /// selection while it follows it.
  @internal
  WorkingPlane get workingPlane3D {
    final state = scope.designer3D;
    return state.followSelection.value
        ? state.planeAt(selectionEntities)
        : state.plane;
  }

  /// Drops everything selected straight down onto what is under it (or
  /// the working plane), as one undo step. How many moved.
  @internal
  int dropSelectionToGround() {
    final picker = RayEntityPicker(tests: () => scope.pickTests);
    return entities.dropSelectionToGround(
      below: (ray, ignore) => picker.placementAlong(
        ray,
        engine.world.entities.where((e) => _isDrawn(e) && !ignore.contains(e)),
      ),
      plane: workingPlane3D,
    );
  }

  /// Copies the selection as [spec] lays them out, about the gizmo's
  /// pivot, as one undo step.
  @internal
  void arraySelection3D(Array3DSpec spec) => entities.arraySelection3D(
    history,
    spec,
    SelectionPivot.of(selectionEntities, scope.designer3D.pivotMode.value),
  );

  /// The prefabs a 3-D scene can be given from the viewport menu: the
  /// built-in ones and every module's that place in 3-D, whichever kit the
  /// Level Designer has chosen, then each variant of those it applies to
  /// (a Solid of every shape).
  @internal
  List<PrefabDefinition> get prefabsInSpace {
    final base = [
      for (final module in scope.modules.withBuiltIns)
        for (final prefab in [...module.prefabs, ...module.sharedPrefabs])
          if (prefab.dimensions.allows(SceneMode.threeD)) prefab,
    ];
    return [
      ...base,
      for (final variant in scope.prefabVariants)
        for (final prefab in base)
          if (variant.offersFor(prefab)) variant.of(prefab),
    ];
  }

  /// The points the selected entity lets the author drag, while authoring
  /// with one entity selected: what the modules' [ViewportHandles] offer.
  @internal
  List<ViewportHandle> get selectionHandles {
    if (!isAuthoring.value || sceneState.hasMultiSelection) return const [];
    final entity = sceneState.selectedEntity.value;
    if (entity == null || !entity.isAlive) return const [];
    final mode = sceneState.editingMode;
    return [
      for (final provider in scope.viewportHandles)
        if (provider.dimensions.allows(mode))
          ...provider.handlesOf(entity, scope),
    ];
  }

  /// Places [prefab] at [at], selected, as one undo step.
  @internal
  Entity placePrefab(PrefabDefinition prefab, SurfacePoint at) =>
      entities.placePrefab(prefab, at);

  /// In 3-D: frames the selection — or, with [all] or nothing selected,
  /// everything drawn.
  @internal
  void frameInSpace({bool all = false}) {
    final view = scope.editorView;
    if (view is! OrbitFlyEditorView) return;
    final box = Aabb3(), one = Aabb3();
    final picked = all ? const <Entity>[] : selectionEntities;
    for (final e
        in picked.isEmpty ? engine.world.entities.where(_isDrawn) : picked) {
      if (RayEntityPicker.boundsOf(e, one)) box.addBox(one);
    }
    view.focusOn(box);
  }

  /// In 3-D: looks along an axis ([yaw], [pitch] in radians), turning about
  /// the point the view pivots on.
  @internal
  void viewAlong({required double yaw, required double pitch}) {
    if (scope.editorView case final OrbitFlyEditorView view) {
      view.viewFrom(yaw: yaw, pitch: pitch);
    }
  }

  /// Opens the Level Designer on the map on [entity], ready to paint: the
  /// map selected and painted, the Stamp in hand unless a tile tool already
  /// is, and the view on what is painted — what double-clicking the Level
  /// Map in the scene tree does.
  @internal
  void designLevelMap(Entity entity) {
    sceneState.selectEntity(entity);
    openLevelDesigner();
    scope.tiles.selectMap(entity);
    final session = designer.value;
    if (session != null && session.controller.activeGroup != ToolGroups.tiles) {
      session.setTool(TileTools.stamp);
    }
    final target = scope.mapDocs.resolve(entity);
    if (target == null) return;
    var centre = target.origin;
    final layer = scope.tiles.peekLayer(target);
    final used = layer?.cells.usedBounds;
    if (layer != null && used != null) {
      final g = target.geometry;
      final a = g.cellCenter(used.left.toInt(), used.top.toInt());
      final b = g.cellCenter(used.right.toInt() - 1, used.bottom.toInt() - 1);
      centre += Offset(layer.offsetX, layer.offsetY) + Offset.lerp(a, b, 0.5)!;
    }
    engine.camera.mainCamera.position = centre;
  }

  /// Deletes everything selected, as one undoable action.
  @internal
  void deleteSelection() => entities.deleteSelection(history);

  /// Duplicates everything selected, offset by one grid cell so the copies
  /// are visible rather than hidden exactly behind the originals.
  @internal
  void duplicateSelection() =>
      entities.duplicateSelection(history, gridSize: gridSize.value);

  /// Repeats the selection [count] times, each copy [step] further along.
  @internal
  void arraySelection({required int count, required Offset step}) =>
      entities.arraySelection(history, count: count, step: step);
}
