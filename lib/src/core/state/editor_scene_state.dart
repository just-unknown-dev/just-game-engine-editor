import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Bridges the authoring scene graph ([Scene]/[SceneNode]) with the live ECS
/// world ([Entity]/[TransformComponent]).
///
/// All mutations go through this class so both representations stay in sync.
class EditorSceneState extends ChangeNotifier {
  Scene? _activeScene;
  Entity? _selectedEntity;
  SceneNode? _selectedNode;
  bool _isDirty = false;
  final Map<EntityId, SceneNode> _entityNodeMap = {};
  final Set<EntityId> _multiSelectedIds = {};
  bool _gridSnappingEnabled = true;
  double _gridSize = 32.0;

  // ── Getters ──────────────────────────────────────────────────────────────

  Scene? get activeScene => _activeScene;
  Entity? get selectedEntity => _selectedEntity;
  SceneNode? get selectedNode => _selectedNode;
  bool get isDirty => _isDirty;
  bool get hasScene => _activeScene != null;
  Map<EntityId, SceneNode> get entityNodeMap =>
      Map.unmodifiable(_entityNodeMap);

  /// All entity IDs in the multi-selection (includes the primary selected entity).
  Set<EntityId> get multiSelectedIds => Set.unmodifiable(_multiSelectedIds);

  /// `true` when two or more entities are selected simultaneously.
  bool get hasMultiSelection => _multiSelectedIds.length > 1;
  bool get gridSnappingEnabled => _gridSnappingEnabled;
  double get gridSize => _gridSize;

  bool isInMultiSelection(EntityId id) => _multiSelectedIds.contains(id);

  // ── Scene lifecycle ──────────────────────────────────────────────────────

  /// Open [scene] and link entity IDs to scene nodes via [entityNodeMap].
  void openScene(Scene scene, Map<EntityId, SceneNode> entityNodeMap) {
    _activeScene = scene;
    _entityNodeMap
      ..clear()
      ..addAll(entityNodeMap);
    _selectedEntity = null;
    _selectedNode = null;
    _multiSelectedIds.clear();
    _isDirty = false;
    notifyListeners();
  }

  /// Close the active scene and clear all editor state.
  void closeScene() {
    _activeScene = null;
    _entityNodeMap.clear();
    _selectedEntity = null;
    _selectedNode = null;
    _multiSelectedIds.clear();
    _isDirty = false;
    notifyListeners();
  }

  // ── Selection ────────────────────────────────────────────────────────────

  void selectEntity(Entity entity) {
    if (_selectedEntity?.id == entity.id && !hasMultiSelection) return;
    _selectedEntity = entity;
    _selectedNode = _entityNodeMap[entity.id];
    _multiSelectedIds
      ..clear()
      ..add(entity.id);
    notifyListeners();
  }

  /// Toggles [entity] in/out of the multi-selection (Shift+click behaviour).
  ///
  /// If nothing is selected, falls back to normal single selection.
  /// Removing the primary entity makes the next remaining entity the primary.
  void toggleMultiSelect(Entity entity) {
    if (_multiSelectedIds.isEmpty) {
      // Nothing selected yet — behave like a normal single select.
      selectEntity(entity);
      return;
    }

    if (_multiSelectedIds.contains(entity.id)) {
      _multiSelectedIds.remove(entity.id);
      if (_multiSelectedIds.isEmpty) {
        _selectedEntity = null;
        _selectedNode = null;
      } else if (_selectedEntity?.id == entity.id) {
        // Primary was removed — promote the first remaining ID as primary.
        // We can't look up the entity object here, so we just clear primary.
        // The next notifyListeners will re-derive from the set in the UI.
        _selectedEntity = null;
        _selectedNode = null;
      }
    } else {
      // Add current primary to the set if it was a single-select before.
      if (_selectedEntity != null) _multiSelectedIds.add(_selectedEntity!.id);
      _multiSelectedIds.add(entity.id);
      _selectedEntity = entity;
      _selectedNode = _entityNodeMap[entity.id];
    }
    notifyListeners();
  }

  /// Clears all multi-selection, keeping a single primary selection if present.
  void clearMultiSelection() {
    if (!hasMultiSelection) return;
    _multiSelectedIds.clear();
    if (_selectedEntity != null) _multiSelectedIds.add(_selectedEntity!.id);
    notifyListeners();
  }

  /// Selects [entities] as a contiguous range, keeping [anchor] as primary.
  void selectRange(List<Entity> entities, {required Entity anchor}) {
    if (entities.isEmpty) return;
    _multiSelectedIds
      ..clear()
      ..addAll(entities.map((e) => e.id));
    _selectedEntity = anchor;
    _selectedNode = _entityNodeMap[anchor.id];
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedEntity == null && _multiSelectedIds.isEmpty) return;
    _selectedEntity = null;
    _selectedNode = null;
    _multiSelectedIds.clear();
    notifyListeners();
  }

  // ── Dirty flag ───────────────────────────────────────────────────────────

  void markDirty() {
    if (_isDirty) return;
    _isDirty = true;
    notifyListeners();
  }

  void markClean() {
    if (!_isDirty) return;
    _isDirty = false;
    notifyListeners();
  }

  /// Forces a UI rebuild without changing the dirty flag.
  ///
  /// Useful after structural mutations (adding/removing components) that the
  /// dirty flag alone wouldn't trigger a rebuild for.
  void refresh() => notifyListeners();

  void setGridSnapping({
    required bool enabled,
    required double gridSize,
    bool notify = false,
  }) {
    final normalizedSize = gridSize <= 0 ? 32.0 : gridSize;
    final changed =
        _gridSnappingEnabled != enabled || _gridSize != normalizedSize;
    _gridSnappingEnabled = enabled;
    _gridSize = normalizedSize;
    if (changed && notify) {
      notifyListeners();
    }
  }

  // ── Transform mutations (keep ECS + SceneNode in sync) ───────────────────

  /// Translate [entity] by [delta] in world space.
  void applyTranslation(Entity entity, Offset delta) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    transform.translateXY(delta.dx, delta.dy);
    if (_gridSnappingEnabled) {
      final snapped = _snapPosition(transform.position.toOffset());
      transform.setPositionXY(snapped.dx, snapped.dy);
    }
    _entityNodeMap[entity.id]?.localPosition = transform.position.toOffset();
    markDirty();
    notifyListeners();
  }

  /// Rotate [entity] by [deltaRad] radians.
  void applyRotation(Entity entity, double deltaRad) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    transform.rotate(deltaRad);
    final node = _entityNodeMap[entity.id];
    if (node != null) node.localRotation += deltaRad;
    markDirty();
    notifyListeners();
  }

  /// Scale [entity] by a multiplicative [factor] on both axes.
  void applyScale(Entity entity, double factor) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    transform.scale.x *= factor;
    transform.scale.y *= factor;
    if (_gridSnappingEnabled) {
      transform.scale.x = _snapScale(transform.scale.x);
      transform.scale.y = _snapScale(transform.scale.y);
    }
    final node = _entityNodeMap[entity.id];
    if (node != null) {
      node.localScale = (transform.scale.x + transform.scale.y) / 2;
    }
    markDirty();
    notifyListeners();
  }

  /// Set [entity]'s position directly (used by inspector text fields).
  void setPosition(Entity entity, Offset position) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    final nextPosition = _gridSnappingEnabled
        ? _snapPosition(position)
        : position;
    transform.setPositionXY(nextPosition.dx, nextPosition.dy);
    final node = _entityNodeMap[entity.id];
    if (node != null) node.localPosition = nextPosition;
    markDirty();
    notifyListeners();
  }

  /// Set [entity]'s rotation directly (used by inspector text fields).
  void setRotation(Entity entity, double radians) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    transform.rotation = radians;
    final node = _entityNodeMap[entity.id];
    if (node != null) node.localRotation = radians;
    markDirty();
    notifyListeners();
  }

  /// Set [entity]'s scale directly.
  void setScale(Entity entity, Offset scale) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    final sx = _gridSnappingEnabled ? _snapScale(scale.dx) : scale.dx;
    final sy = _gridSnappingEnabled ? _snapScale(scale.dy) : scale.dy;
    transform.scale.x = sx;
    transform.scale.y = sy;
    final node = _entityNodeMap[entity.id];
    if (node != null) node.localScale = (sx + sy) / 2;
    markDirty();
    notifyListeners();
  }

  /// Set [entity]'s X scale only (used by inspector).
  void setScaleX(Entity entity, double x) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    final sx = _gridSnappingEnabled ? _snapScale(x) : x;
    transform.scale.x = sx;
    final node = _entityNodeMap[entity.id];
    if (node != null) node.localScale = (sx + transform.scale.y) / 2;
    markDirty();
    notifyListeners();
  }

  /// Set [entity]'s Y scale only (used by inspector).
  void setScaleY(Entity entity, double y) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    final sy = _gridSnappingEnabled ? _snapScale(y) : y;
    transform.scale.y = sy;
    final node = _entityNodeMap[entity.id];
    if (node != null) node.localScale = (transform.scale.x + sy) / 2;
    markDirty();
    notifyListeners();
  }

  Offset _snapPosition(Offset value) {
    final gx = (value.dx / _gridSize).roundToDouble() * _gridSize;
    final gy = (value.dy / _gridSize).roundToDouble() * _gridSize;
    return Offset(gx, gy);
  }

  double _snapScale(double value) {
    final step = 1 / _gridSize;
    return (value / step).roundToDouble() * step;
  }

  /// Rename [entity] and keep the linked [SceneNode] in sync.
  void renameEntity(Entity entity, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    entity.name = trimmed;

    final oldNode = _entityNodeMap[entity.id];
    if (oldNode != null) {
      final parent = oldNode.parent;
      final newNode = SceneNode(trimmed)
        ..localPosition = oldNode.localPosition
        ..localRotation = oldNode.localRotation
        ..localScale = oldNode.localScale
        ..isActive = oldNode.isActive;
      if (parent != null) {
        parent.removeChild(oldNode);
        parent.addChild(newNode);
      }
      _entityNodeMap[entity.id] = newNode;
      if (_selectedEntity?.id == entity.id) _selectedNode = newNode;
    }

    markDirty();
    notifyListeners();
  }

  /// Register a newly discovered entity that has no matching [SceneNode] yet.
  ///
  /// Creates a [SceneNode] from the entity's current [TransformComponent] and
  /// adds it as a child of [scene.root].
  void registerEntity(Entity entity) {
    if (!hasScene) return;
    if (_entityNodeMap.containsKey(entity.id)) return;

    final transform = entity.getComponent<TransformComponent>();
    final node = SceneNode(entity.name ?? 'entity_${entity.id}')
      ..localPosition = transform?.position.toOffset() ?? Offset.zero
      ..localRotation = transform?.rotation ?? 0.0
      ..localScale = transform?.scale.x ?? 1.0;

    _activeScene!.addNode(node);
    _entityNodeMap[entity.id] = node;
    markDirty();
  }

  /// Removes the entity's authoring [SceneNode] from the scene graph.
  ///
  /// Called by [JustGameEditorPlugin.deleteEntity] before destroying the ECS
  /// entity. Clears selection and marks the scene dirty.
  void removeEntityNode(EntityId id) {
    final node = _entityNodeMap.remove(id);
    if (node != null) _activeScene?.removeNode(node);
    _multiSelectedIds.remove(id);
    if (_selectedEntity?.id == id) {
      _selectedEntity = null;
      _selectedNode = null;
    }
    _isDirty = true;
    notifyListeners();
  }

  // ── Clipboard ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>>? _clipboardJson;

  bool get hasClipboard => _clipboardJson != null;

  List<Map<String, dynamic>>? get clipboardJson =>
      _clipboardJson != null ? List.unmodifiable(_clipboardJson!) : null;

  /// Stores a snapshot of [components] in the clipboard for paste.
  void setClipboard(List<Map<String, dynamic>> components) {
    _clipboardJson = List.from(components);
    notifyListeners();
  }
}
