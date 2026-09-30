import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../dev/editor_dev_flags.dart';

/// The authoring state of the open [Scene]: selection, dirtiness, the
/// order of the top-level entities, and the transform edits the gizmos and
/// the inspector make on the live ECS world ([Entity]/[TransformComponent]).
///
/// A scene's hierarchy is its entities (`ParentComponent`,
/// `ChildrenComponent`); there is no separate node graph to keep in step.
///
/// Every piece of state is a [Signal]. A panel watches the ones it reads and
/// rebuilds for nothing else: the inspector follows [selectedEntity], the save
/// button follows [isDirty], the scene picker follows [activeScene]. What no
/// signal of its own captures — a transform edit, a rename, a component added
/// or removed — bumps [revision].
class EditorSceneState {
  /// The scene being edited, or null between scenes.
  final Signal<Scene?> activeScene = Signal(null, debugLabel: 'activeScene');

  /// How the open scene is authored, from its file (2-D when it says
  /// nothing). See [editingMode] for the mode the editor works in.
  final Signal<SceneMode> sceneMode = Signal(
    SceneMode.twoD,
    debugLabel: 'sceneMode',
  );

  /// The mode the inspector, tools and pickers work in: the scene's own —
  /// except that 3-D authoring is not switched on yet
  /// ([EditorDevFlags.allow3DSceneMode]), so a 3-D scene is edited with the
  /// 2-D defaults. Its mode is kept when it is saved.
  SceneMode get editingMode =>
      sceneMode.value == SceneMode.threeD && !EditorDevFlags.allow3DSceneMode
      ? SceneMode.twoD
      : sceneMode.value;

  /// The primary selection.
  final Signal<Entity?> selectedEntity = Signal(
    null,
    debugLabel: 'selectedEntity',
  );

  /// Whether there are unsaved changes.
  final Signal<bool> isDirty = Signal(false, debugLabel: 'isDirty');

  /// Every entity id in the selection, the primary included.
  ///
  /// Always a fresh unmodifiable set: a signal compares by identity, so a set
  /// mutated in place would change without anyone hearing about it.
  final Signal<Set<EntityId>> multiSelectedIds = Signal(
    const {},
    debugLabel: 'multiSelectedIds',
  );

  /// Whether transform edits snap to the grid.
  final Signal<bool> gridSnappingEnabled = Signal(
    true,
    debugLabel: 'gridSnappingEnabled',
  );

  /// The grid cell size, in world units.
  final Signal<double> gridSize = Signal(32.0, debugLabel: 'gridSize');

  /// Components copied for paste, as JSON; null when nothing was copied.
  final Signal<List<Map<String, dynamic>>?> clipboard = Signal(
    null,
    debugLabel: 'clipboard',
  );

  /// Bumped by [refresh] and by every edit that changes entities without
  /// changing any other signal. Watch it to redraw a view of the world.
  final Signal<int> revision = Signal(0, debugLabel: 'sceneRevision');

  /// Which entities may be selected right now; null means any.
  ///
  /// The Level Designer narrows it to its Level Map while it is open, so
  /// nothing else in the scene can be picked in the viewport, clicked in
  /// the tree or reached with the keys. Set through [setSelectable], which
  /// also lets go of whatever it no longer allows.
  final Signal<bool Function(Entity entity)?> selectable = Signal(
    null,
    debugLabel: 'selectable',
  );

  /// What order the scene's top-level entities are in.
  ///
  /// The world keeps no order, so without this the roots listed and saved
  /// in whatever order they happened to be created and could not be
  /// rearranged. Read through [rootOrder], which drops anything that has
  /// since been destroyed or given a parent.
  final List<EntityId> _rootOrder = [];

  // Mirrors multiSelectedIds so toggleMultiSelect can promote a new primary
  // Entity object (not just an id) when the current primary is deselected.
  final Map<EntityId, Entity> _multiSelectedEntities = {};

  // ── Derived reads ────────────────────────────────────────────────────────

  bool get hasScene => activeScene.value != null;

  /// `true` when two or more entities are selected simultaneously.
  bool get hasMultiSelection => multiSelectedIds.value.length > 1;

  bool isInMultiSelection(EntityId id) => multiSelectedIds.value.contains(id);

  bool get hasClipboard => clipboard.value != null;

  /// Whether anything at all is selected.
  bool get hasAnySelection =>
      selectedEntity.value != null || multiSelectedIds.value.isNotEmpty;

  /// Whether [entity] may be selected right now; see [selectable].
  bool canSelect(Entity entity) => selectable.value?.call(entity) ?? true;

  /// Allows only what [test] passes to be selected from now on, or
  /// anything when it is null, and deselects what it refuses.
  void setSelectable(bool Function(Entity entity)? test) {
    batch(() {
      selectable.value = test;
      if (test == null || !hasAnySelection) return;
      final primary = selectedEntity.value;
      final kept = <EntityId, Entity>{
        if (primary != null && test(primary)) primary.id: primary,
        for (final e in _multiSelectedEntities.values)
          if (test(e)) e.id: e,
      };
      final unchanged =
          (primary == null || kept.containsKey(primary.id)) &&
          kept.length == multiSelectedIds.value.length;
      if (unchanged) return;
      final anchor = primary != null && kept.containsKey(primary.id)
          ? primary
          : kept.values.firstOrNull;
      _multiSelectedEntities
        ..clear()
        ..addAll(kept);
      selectedEntity.value = anchor;
      _setMultiSelection(kept.keys);
    });
  }

  void _setMultiSelection(Iterable<EntityId> ids) =>
      multiSelectedIds.value = Set.unmodifiable(ids);

  // ── Scene lifecycle ──────────────────────────────────────────────────────

  /// Open [scene], its top-level entities in [rootOrder].
  void openScene(Scene scene, {List<EntityId> rootOrder = const []}) {
    batch(() {
      activeScene.value = scene;
      sceneMode.value = scene.mode;
      _rootOrder
        ..clear()
        ..addAll(rootOrder);
      selectedEntity.value = null;
      _multiSelectedEntities.clear();
      _setMultiSelection(const []);
      isDirty.value = false;
      refresh();
    });
  }

  /// Close the active scene and clear all editor state.
  void closeScene() {
    batch(() {
      activeScene.value = null;
      sceneMode.value = SceneMode.twoD;
      _rootOrder.clear();
      selectedEntity.value = null;
      _multiSelectedEntities.clear();
      _setMultiSelection(const []);
      isDirty.value = false;
      refresh();
    });
  }

  // ── Selection ────────────────────────────────────────────────────────────

  void selectEntity(Entity entity) {
    if (!canSelect(entity)) return;
    if (selectedEntity.value?.id == entity.id && !hasMultiSelection) {
      return;
    }
    batch(() {
      selectedEntity.value = entity;
      _multiSelectedEntities
        ..clear()
        ..[entity.id] = entity;
      _setMultiSelection([entity.id]);
    });
  }

  /// Toggles [entity] in/out of the multi-selection (Shift+click behaviour).
  ///
  /// If nothing is selected, falls back to normal single selection.
  /// Removing the primary entity makes the next remaining entity the primary.
  void toggleMultiSelect(Entity entity) {
    if (!canSelect(entity)) return;
    final ids = {...multiSelectedIds.value};
    if (ids.isEmpty) {
      // Nothing selected yet — behave like a normal single select.
      selectEntity(entity);
      return;
    }

    batch(() {
      if (ids.contains(entity.id)) {
        ids.remove(entity.id);
        _multiSelectedEntities.remove(entity.id);
        if (ids.isEmpty) {
          selectedEntity.value = null;
        } else if (selectedEntity.value?.id == entity.id) {
          // Primary was removed — promote another remaining id as primary.
          final nextId = ids.first;
          selectedEntity.value = _multiSelectedEntities[nextId];
        }
      } else {
        // Add current primary to the set if it was a single-select before.
        final primary = selectedEntity.value;
        if (primary != null) {
          ids.add(primary.id);
          _multiSelectedEntities[primary.id] = primary;
        }
        ids.add(entity.id);
        _multiSelectedEntities[entity.id] = entity;
        selectedEntity.value = entity;
      }
      _setMultiSelection(ids);
    });
  }

  /// Clears all multi-selection, keeping a single primary selection if present.
  void clearMultiSelection() {
    if (!hasMultiSelection) return;
    final primary = selectedEntity.value;
    _multiSelectedEntities.clear();
    if (primary != null) _multiSelectedEntities[primary.id] = primary;
    _setMultiSelection([?primary?.id]);
  }

  /// Selects [entities] as a contiguous range, keeping [anchor] as primary.
  /// What may not be selected right now is left out.
  void selectRange(List<Entity> entities, {required Entity anchor}) {
    if (selectable.value != null) {
      entities = entities.where(canSelect).toList();
      if (entities.isEmpty) return;
      if (!canSelect(anchor)) anchor = entities.first;
    }
    if (entities.isEmpty) return;
    batch(() {
      _multiSelectedEntities
        ..clear()
        ..addEntries(entities.map((e) => MapEntry(e.id, e)));
      selectedEntity.value = anchor;
      _setMultiSelection(entities.map((e) => e.id));
    });
  }

  void clearSelection() {
    if (!hasAnySelection) return;
    batch(() {
      selectedEntity.value = null;
      _multiSelectedEntities.clear();
      _setMultiSelection(const []);
    });
  }

  // ── Dirty flag ───────────────────────────────────────────────────────────

  /// The scene's top-level entities, in the order they are shown and
  /// saved. [world] is asked which of them are still roots.
  List<EntityId> rootOrder(World world) {
    final live = <EntityId>[];
    for (final id in _rootOrder) {
      final entity = world.getEntity(id);
      // Alive, not enabled: an entity switched off is still in the
      // scene and still where it was. Reading `isActive` here dropped
      // it from the remembered order, and the pass below then put it
      // back at the end — so switching a row off sent it to the bottom.
      if (entity == null || !entity.isAlive) continue;
      if (entity.getComponent<ParentComponent>()?.parentId != null) continue;
      live.add(id);
    }
    // Anything the editor never saw created — a scene loaded around it, a
    // system's own entity — goes last rather than being left out.
    for (final entity in world.entities) {
      if (!entity.isAlive) continue;
      if (entity.getComponent<ParentComponent>()?.parentId != null) continue;
      if (!live.contains(entity.id)) live.add(entity.id);
    }
    return live;
  }

  /// Puts [id] at [index] among the roots. Used by the reorder command.
  void moveRoot(EntityId id, int index) {
    _rootOrder.remove(id);
    _rootOrder.insert(index.clamp(0, _rootOrder.length), id);
    _edited();
  }

  /// Where [id] sits among the roots, or -1.
  int rootIndexOf(EntityId id) => _rootOrder.indexOf(id);

  void markDirty() => isDirty.value = true;

  void markClean() => isDirty.value = false;

  /// Tells every view of the world to redraw, without changing the dirty
  /// flag. Called after structural mutations (adding/removing components)
  /// that no other signal captures.
  void refresh() => revision.value++;

  /// Set by [JustGameEditorPlugin] to re-register game custom components after
  /// a component refresh or hot-reload.
  VoidCallback? onComponentsRefreshed;

  /// Triggers a custom-component re-registration (e.g. after component refresh
  /// completes) and then rebuilds the UI.
  void reloadCustomComponents() {
    onComponentsRefreshed?.call();
    refresh();
  }

  void setGridSnapping({required bool enabled, required double gridSize}) {
    batch(() {
      gridSnappingEnabled.value = enabled;
      this.gridSize.value = gridSize <= 0 ? 32.0 : gridSize;
    });
  }

  // ── Transform mutations ──────────────────────────────────────────────────

  /// A transform edit: the world changed, so it is dirty and views redraw.
  void _edited() => batch(() {
    markDirty();
    refresh();
  });

  /// Bring [entity]'s part of the hierarchy up to date: its own offset from
  /// its parent, and its children's places under it.
  ///
  /// Called before an edit — so the children's offsets are known even when
  /// the game's clock has not run since the scene loaded — and after it, so
  /// they follow. The world's own pass does the same once a frame, but while
  /// authoring the game's time stands still.
  void _settle(Entity entity) =>
      entity.world?.transformHierarchy.propagateFrom(entity);

  /// Translate [entity] by [delta] in world space.
  void applyTranslation(Entity entity, Offset delta) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    transform.translateXY(delta.dx, delta.dy);
    if (gridSnappingEnabled.value) {
      final snapped = _snapPosition(transform.position.toOffset());
      transform.setPositionXY(snapped.dx, snapped.dy);
    }
    _settle(entity);
    _edited();
  }

  /// What a snapped scale moves in — 0.1 is 10 % — and a snapped turn, in
  /// radians. Set from the settings; snapping itself is
  /// [gridSnappingEnabled].
  double scaleStep = 0.1;

  /// What moving snaps in, in world units; 0 is [gridSize].
  double moveStep = 0;
  double rotationStep = 0.2617993877991494; // 15°

  /// [radians] on the nearest [rotationStep] while snapping.
  double snapRotation(double radians) =>
      gridSnappingEnabled.value && rotationStep > 0
      ? (radians / rotationStep).roundToDouble() * rotationStep
      : radians;

  /// Rotate [entity] by [deltaRad] radians.
  void applyRotation(Entity entity, double deltaRad) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    transform.rotate(deltaRad);
    _settle(entity);
    _edited();
  }

  /// Scale [entity] by a multiplicative [factor] on both axes.
  ///
  /// Clamped to [0.01, 50.0] — without this, a corner-scale gizmo drag that
  /// passes exactly through the entity's pivot yields `factor == 0`, which
  /// would permanently zero the scale (0 * anything stays 0 on every
  /// subsequent drag).
  void applyScale(Entity entity, double factor) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    transform.scale.x = (transform.scale.x * factor).clamp(0.01, 50.0);
    transform.scale.y = (transform.scale.y * factor).clamp(0.01, 50.0);
    if (gridSnappingEnabled.value) {
      transform.scale.x = _snapScale(transform.scale.x);
      transform.scale.y = _snapScale(transform.scale.y);
    }
    _settle(entity);
    _edited();
  }

  /// Called after an edit made straight on [entity]'s components (the
  /// inspector, a designer tool), for anything that mirrors them. Nothing
  /// does now that the scene has no node graph; kept so callers need not
  /// change. It must never move the hierarchy: designer tools carry
  /// children themselves and would move them twice.
  void syncEntityNode(Entity entity) {}

  /// Set [entity]'s position directly (used by inspector text fields).
  void setPosition(Entity entity, Offset position) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    final nextPosition = gridSnappingEnabled.value
        ? _snapPosition(position)
        : position;
    transform.setPositionXY(nextPosition.dx, nextPosition.dy);
    _settle(entity);
    _edited();
  }

  /// Set [entity]'s rotation directly (used by inspector text fields).
  void setRotation(Entity entity, double radians) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    transform.angle = radians;
    _settle(entity);
    _edited();
  }

  /// Set [entity]'s scale directly.
  void setScale(Entity entity, Offset scale) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    final sx = gridSnappingEnabled.value ? _snapScale(scale.dx) : scale.dx;
    final sy = gridSnappingEnabled.value ? _snapScale(scale.dy) : scale.dy;
    transform.scale.x = sx;
    transform.scale.y = sy;
    _settle(entity);
    _edited();
  }

  /// Set [entity]'s X scale only (used by inspector).
  void setScaleX(Entity entity, double x) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    final sx = gridSnappingEnabled.value ? _snapScale(x) : x;
    transform.scale.x = sx;
    _settle(entity);
    _edited();
  }

  /// Set [entity]'s Y scale only (used by inspector).
  void setScaleY(Entity entity, double y) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _settle(entity);
    final sy = gridSnappingEnabled.value ? _snapScale(y) : y;
    transform.scale.y = sy;
    _settle(entity);
    _edited();
  }

  Offset _snapPosition(Offset value) {
    final size = moveStep > 0 ? moveStep : gridSize.value;
    final gx = (value.dx / size).roundToDouble() * size;
    final gy = (value.dy / size).roundToDouble() * size;
    return Offset(gx, gy);
  }

  double _snapScale(double value) {
    final step = scaleStep;
    if (step <= 0) return value;
    // Never snapped to nothing: the smallest scale is one step.
    return ((value / step).roundToDouble() * step).clamp(step, 50.0);
  }

  /// Rename [entity].
  void renameEntity(Entity entity, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    entity.name = trimmed;
    _edited();
  }

  /// Register an entity just made in the open scene: it joins the end of
  /// the top level unless it has a parent, and the scene becomes dirty.
  void registerEntity(Entity entity) {
    if (!hasScene) return;
    // A new entity is the last root until something parents it. The world
    // has no order of its own, so this is the only record of what order
    // the top level is in, and it is what the scene file is written in.
    if (entity.getComponent<ParentComponent>()?.parentId == null &&
        !_rootOrder.contains(entity.id)) {
      _rootOrder.add(entity.id);
    }
    markDirty();
  }

  /// Forgets an entity about to be destroyed: out of the top level and the
  /// selection, and the scene becomes dirty.
  ///
  /// Called by [JustGameEditorPlugin.deleteEntity] before destroying the ECS
  /// entity.
  void removeEntityNode(EntityId id) {
    batch(() {
      _rootOrder.remove(id);
      _multiSelectedEntities.remove(id);
      _setMultiSelection(multiSelectedIds.value.where((e) => e != id));
      if (selectedEntity.value?.id == id) {
        selectedEntity.value = null;
      }
      _edited();
    });
  }

  // ── Clipboard ────────────────────────────────────────────────────────────

  /// Stores a snapshot of [components] in the clipboard for paste.
  void setClipboard(List<Map<String, dynamic>> components) {
    clipboard.value = List.unmodifiable(List.of(components));
  }

  void dispose() {
    for (final s in [
      activeScene,
      selectedEntity,
      sceneMode,
      isDirty,
      multiSelectedIds,
      gridSnappingEnabled,
      gridSize,
      clipboard,
      revision,
      selectable,
    ]) {
      s.dispose();
    }
  }
}
