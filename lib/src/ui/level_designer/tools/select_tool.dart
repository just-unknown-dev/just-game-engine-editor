import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/state/editor_scene_state.dart';
import '../state/component_resizer.dart';
import '../state/designer_geometry.dart';
import '../state/editor_commands.dart';
import '../../../core/serialization/scene_codec.dart';
import '../state/editor_history.dart';
import '../state/selection_handle_layout.dart';
import '../state/smart_snap.dart';
import '../state/snap_provider.dart';
import 'level_tool.dart';
import 'tool_registry.dart';

enum _Gesture { none, marquee, move, resize, rotate }

/// Select, move, resize and rotate — the tool most of a level is built with.
///
/// - Press empty space and drag: marquee. Ctrl adds to the selection.
/// - Press an entity: select it; drag to move the whole selection.
///   Alt at the start of the drag moves a copy instead.
/// - Drag one of the eight handles on the selection's bounds: resize every
///   selected entity in proportion. Shift keeps the aspect ratio, Alt resizes
///   about the centre.
/// - Drag the knob above the bounds: rotate about the selection's centre, in
///   15 degree steps.
///
/// While dragging, edges and centres snap to other entities and ruler guides,
/// then to the grid. Hold Ctrl to place freely.
class SelectTool extends LevelToolHandler {
  SelectTool({
    required this.sceneState,
    required this.history,
    required this.codec,
    this.layout = const SelectionHandleLayout(),
    String Function(String prefix)? uniqueName,
  }) : _uniqueName = uniqueName ?? ((prefix) => prefix);

  /// Encodes and decodes components; the scope's codec.
  final SceneCodec codec;

  /// Shared selection state, including the multi-selection set.
  final EditorSceneState sceneState;

  /// Where edits are recorded.
  final EditorHistory history;

  final String Function(String prefix) _uniqueName;

  /// Where the handles sit and how they feel; the scope's.
  final SelectionHandleLayout layout;

  @override
  String get id => BuiltInTools.select;

  @override
  String get label => 'Select';

  @override
  IconData get icon => Icons.near_me;

  @override
  String? get shortcut => 'V';

  @override
  String? get description =>
      'Marquee on empty space; drag to move, Alt+drag to copy; drag a handle '
      'to resize or the knob to rotate';

  @override
  int get order => 10;

  _Gesture _gesture = _Gesture.none;

  // Marquee.
  Offset? _marqueeStart;
  Set<jge.EntityId> _additiveBase = const {};

  // Shared by move, resize and rotate.
  Offset _origin = Offset.zero;
  List<jge.Entity> _targets = const [];
  List<TransformSnapshot> _before = const [];
  Rect _startBounds = Rect.zero;
  List<Rect> _snapRects = const [];
  List<double> _guideXs = const [];
  List<double> _guideYs = const [];

  // Resize.
  ResizeHandle? _handle;
  List<EntitySpec> _beforeSpecs = const [];

  // Rotate.
  double _startAngle = 0;

  // Alt+drag duplicate.
  jge.World? _world;
  bool _duplicating = false;
  List<jge.Entity> _originalSelection = const [];

  @override
  bool onPointerDown(ToolContext context) {
    _world = context.world;
    final selection = _selectionEntities(context.world);
    final bounds = _groupBounds(selection);

    // Handles first: they sit on top of the selection they belong to.
    if (bounds != null && !context.isCtrlDown) {
      final reach = context.pixels(layout.handlePixels);
      final knob = layout.rotateKnobAt(bounds, context.unitsPerPixel);
      if ((context.worldPosition - knob).distance <= reach * 1.5) {
        _begin(context, selection, bounds, _Gesture.rotate);
        _startAngle = _angleFrom(bounds.center, context.worldPosition);
        return true;
      }
      for (final handle in ResizeHandle.values) {
        if ((context.worldPosition - handle.on(bounds)).distance <= reach) {
          _begin(context, selection, bounds, _Gesture.resize);
          _handle = handle;
          _beforeSpecs = selection
              .map((e) => EntitySpec.of(e, codec))
              .toList(growable: false);
          return true;
        }
      }
    }

    final hit = _entityAt(context);
    if (hit == null) {
      // Empty space: start a marquee. Ctrl keeps the existing selection so a
      // second sweep can add to the first.
      _gesture = _Gesture.marquee;
      _marqueeStart = context.worldPosition;
      _additiveBase = context.isCtrlDown
          ? Set<jge.EntityId>.from(sceneState.multiSelectedIds.value)
          : const {};
      if (!context.isCtrlDown) sceneState.clearSelection();
      context.controller.dragRect.value = Rect.fromPoints(
        context.worldPosition,
        context.worldPosition,
      );
      return true;
    }

    if (context.isCtrlDown) {
      sceneState.toggleMultiSelect(hit);
      return true;
    }

    // Pressing an entity that is not part of the current selection replaces
    // the selection; pressing one that *is* keeps it, so a multi-selection can
    // be dragged as a unit rather than collapsing to whatever was grabbed.
    if (!sceneState.isInMultiSelection(hit.id) &&
        sceneState.selectedEntity.value?.id != hit.id) {
      sceneState.selectEntity(hit);
    }

    var targets = _selectionEntities(context.world);
    if (context.isAltDown) {
      _originalSelection = targets;
      targets = _duplicate(context.world, targets);
      _select(targets);
      _duplicating = true;
    }
    final targetBounds = _groupBounds(targets);
    if (targetBounds != null) {
      _begin(context, targets, targetBounds, _Gesture.move);
    }
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    switch (_gesture) {
      case _Gesture.marquee:
        context.controller.dragRect.value = DesignerGeometry.rectFromDrag(
          _marqueeStart!,
          context.worldPosition,
        );
      case _Gesture.move:
        _move(context);
      case _Gesture.resize:
        _resize(context);
      case _Gesture.rotate:
        _rotate(context);
      case _Gesture.none:
        break;
    }
  }

  @override
  void onPointerUp(ToolContext context) {
    switch (_gesture) {
      case _Gesture.marquee:
        _commitMarquee(context, _marqueeStart!);
      case _Gesture.move:
        _commitMove(context);
      case _Gesture.resize:
        _commitResize(context);
      case _Gesture.rotate:
        _commitTransform('Rotate');
      case _Gesture.none:
        break;
    }
    _reset(context);
  }

  @override
  void onCancel() {
    // Put everything back: an abandoned gesture must not leave a half-applied
    // edit behind.
    for (var i = 0; i < _targets.length; i++) {
      if (!_targets[i].isAlive) continue;
      if (_gesture == _Gesture.resize) {
        _beforeSpecs[i].applyTo(_targets[i]);
      } else {
        _before[i].applyTo(_targets[i]);
      }
    }
    if (_duplicating) _discardCopies();
    _reset(null);
  }

  void _begin(
    ToolContext context,
    List<jge.Entity> targets,
    Rect bounds,
    _Gesture gesture,
  ) {
    _gesture = gesture;
    _targets = targets;
    _origin = context.worldPosition;
    _startBounds = bounds;
    // Snapshotted up front so a commit restores exact starting transforms
    // rather than re-applying an inverted delta, which would drift.
    _before = targets.map(TransformSnapshot.of).toList(growable: false);

    // What the selection can snap to, fixed for the gesture: everything
    // visible and pickable except the selection itself.
    final moving = {for (final e in targets) e.id};
    _snapRects = [
      for (final e in context.world.query([jge.TransformComponent]))
        if (e.isActive &&
            !moving.contains(e.id) &&
            context.controller.isPickable(e))
          ?DesignerGeometry.worldBounds(e),
    ];
    final guides = context.controller.guides.value;
    _guideXs = [
      for (final g in guides)
        if (g.isVertical) g.position,
    ];
    _guideYs = [
      for (final g in guides)
        if (!g.isVertical) g.position,
    ];
  }

  void _reset(ToolContext? context) {
    if (context != null) {
      context.controller
        ..dragRect.value = null
        ..snapGuides = const []
        ..spacingGuides = const [];
    }
    _gesture = _Gesture.none;
    _marqueeStart = null;
    _additiveBase = const {};
    _targets = const [];
    _before = const [];
    _beforeSpecs = const [];
    _snapRects = const [];
    _handle = null;
    _duplicating = false;
    _originalSelection = const [];
  }

  // ── Move ──────────────────────────────────────────────────────────────────

  void _move(ToolContext context) {
    var delta = context.worldPosition - _origin;
    var snapX = true;
    var snapY = true;
    // Shift constrains to the dominant axis — the standard way to keep a row
    // of platforms aligned while sliding it.
    if (context.isShiftDown) {
      if (delta.dx.abs() >= delta.dy.abs()) {
        delta = Offset(delta.dx, 0);
        snapY = false;
      } else {
        delta = Offset(0, delta.dy);
        snapX = false;
      }
    }
    final moved =
        delta +
        _snapAdjustment(
          context,
          _startBounds.shift(delta),
          snapX: snapX,
          snapY: snapY,
        );

    for (var i = 0; i < _targets.length; i++) {
      final entity = _targets[i];
      if (!entity.isAlive) continue;
      entity.getComponent<jge.TransformComponent>()?.setPositionXY(
        _before[i].x + moved.dx,
        _before[i].y + moved.dy,
      );
      sceneState.syncEntityNode(entity);
    }
    sceneState.refresh();
    _publishGuides(context, _startBounds.shift(moved));
  }

  /// How far to shift [rect] so it snaps: to a neighbour or ruler guide when
  /// one is close, otherwise to the grid. The selection's edges snap, not the
  /// pointer — the author is lining up platform against platform, and the
  /// cursor is nowhere near the edge that has to meet the neighbour.
  Offset _snapAdjustment(
    ToolContext context,
    Rect rect, {
    bool snapX = true,
    bool snapY = true,
  }) {
    if (!context.snapping) return Offset.zero;
    // Whoever snaps: entities and guides first, the grid last, and anything a
    // module adds wherever its priority puts it.
    return context.snapper
        .resolve(
          SnapRequest(
            moving: rect,
            gridSize: context.gridSize,
            others: _snapRects,
            xLines: _guideXs,
            yLines: _guideYs,
            threshold: context.pixels(layout.snapPixels),
            snapX: snapX,
            snapY: snapY,
            smart: context.smartSnapping,
          ),
        )
        .adjustment;
  }

  void _publishGuides(ToolContext context, Rect rect) {
    final controller = context.controller;
    if (!context.smartSnapping) {
      controller
        ..snapGuides = const []
        ..spacingGuides = const [];
      return;
    }
    controller
      ..snapGuides = SmartSnap.guides(rect, _snapRects)
      ..spacingGuides = SmartSnap.spacing(
        rect,
        _snapRects,
        maxDistance: context.pixels(480),
      );
  }

  void _commitMove(ToolContext context) {
    if (!_duplicating) {
      _commitTransform('Move');
      return;
    }
    if (!_anyTransformChanged()) {
      // Alt-click without a drag: no copy was asked for.
      _discardCopies();
      return;
    }
    final copies = _targets;
    history.pushApplied(
      CreateEntitiesCommand.adopting(
        codec: codec,
        label: copies.length == 1
            ? 'Duplicate ${_originalSelection.first.name ?? 'entity'}'
            : 'Duplicate ${copies.length} entities',
        world: context.world,
        sceneState: sceneState,
        entities: copies,
        onCreated: _select,
      ),
    );
    sceneState.markDirty();
  }

  /// Records a move or rotation as one undo step, if anything changed.
  void _commitTransform(String verb) {
    if (_targets.isEmpty || !_anyTransformChanged()) return;
    final after = [for (final e in _targets) TransformSnapshot.of(e)];
    history.pushApplied(
      TransformCommand(
        label: _targets.length == 1
            ? '$verb ${_targets.first.name ?? 'entity'}'
            : '$verb ${_targets.length} entities',
        entities: List.of(_targets),
        before: List.of(_before),
        after: after,
        sceneState: sceneState,
      ),
    );
    sceneState.markDirty();
  }

  bool _anyTransformChanged() {
    for (var i = 0; i < _targets.length; i++) {
      if (!_targets[i].isAlive) continue;
      if (!_before[i].matches(TransformSnapshot.of(_targets[i]))) return true;
    }
    return false;
  }

  // ── Resize ────────────────────────────────────────────────────────────────

  void _resize(ToolContext context) {
    final handle = _handle!;
    var pointer = context.worldPosition;
    if (context.snapping) {
      // Snap the edge being dragged, which sits under the pointer.
      final adjust = _snapAdjustment(
        context,
        Rect.fromLTWH(pointer.dx, pointer.dy, 0, 0),
        snapX: handle.x != 0,
        snapY: handle.y != 0,
      );
      pointer += adjust;
    }
    final bounds = DesignerGeometry.resizeRect(
      _startBounds,
      handle,
      pointer,
      keepAspect: context.isShiftDown,
      fromCenter: context.isAltDown,
      minExtent: ComponentResizer.minimumExtent,
    );
    final sx = _startBounds.width > 0 ? bounds.width / _startBounds.width : 1.0;
    final sy = _startBounds.height > 0
        ? bounds.height / _startBounds.height
        : 1.0;

    for (var i = 0; i < _targets.length; i++) {
      final entity = _targets[i];
      if (!entity.isAlive) continue;
      // From the captured state every frame, not from the last frame: a
      // resize that shrinks to the minimum and grows back must return to the
      // exact starting size, and cumulative factors cannot.
      _beforeSpecs[i].applyTo(entity);
      ComponentResizer.scale(entity, sx, sy);
      final to = DesignerGeometry.mapPoint(
        Offset(_before[i].x, _before[i].y),
        _startBounds,
        bounds,
      );
      entity.getComponent<jge.TransformComponent>()?.setPositionXY(
        to.dx,
        to.dy,
      );
      sceneState.syncEntityNode(entity);
    }
    sceneState.refresh();
    context.controller.setStatus(
      '${bounds.width.toStringAsFixed(0)} × ${bounds.height.toStringAsFixed(0)}',
    );
    _publishGuides(context, bounds);
  }

  void _commitResize(ToolContext context) {
    final command = EntityStateCommand(
      label: _targets.length == 1
          ? 'Resize ${_targets.first.name ?? 'entity'}'
          : 'Resize ${_targets.length} entities',
      world: context.world,
      sceneState: sceneState,
      ids: [for (final e in _targets) e.id],
      before: _beforeSpecs,
      after: [for (final e in _targets) EntitySpec.of(e, codec)],
    );
    if (!command.changesAnything) return;
    history.pushApplied(command);
    sceneState.markDirty();
  }

  // ── Rotate ────────────────────────────────────────────────────────────────

  void _rotate(ToolContext context) {
    final pivot = _startBounds.center;
    var angle = _angleFrom(pivot, context.worldPosition) - _startAngle;
    if (context.snapping) {
      angle =
          (angle / layout.rotationStep).roundToDouble() * layout.rotationStep;
    }
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    for (var i = 0; i < _targets.length; i++) {
      final entity = _targets[i];
      if (!entity.isAlive) continue;
      final before = _before[i];
      final dx = before.x - pivot.dx;
      final dy = before.y - pivot.dy;
      entity.getComponent<jge.TransformComponent>()
        ?..setPositionXY(
          pivot.dx + dx * cos - dy * sin,
          pivot.dy + dx * sin + dy * cos,
        )
        ..rotation = before.rotation + angle;
      sceneState.syncEntityNode(entity);
    }
    sceneState.refresh();
    context.controller.setStatus('${(angle * 180 / math.pi).round()}°');
  }

  static double _angleFrom(Offset pivot, Offset point) =>
      math.atan2(point.dy - pivot.dy, point.dx - pivot.dx);

  // ── Marquee ───────────────────────────────────────────────────────────────

  void _commitMarquee(ToolContext context, Offset start) {
    final selection = DesignerGeometry.rectFromDrag(
      start,
      context.worldPosition,
    );

    // A click, not a sweep: treat it as "clear selection", which is what
    // clicking empty space should do.
    if (selection.width < 2 && selection.height < 2) {
      if (_additiveBase.isEmpty) sceneState.clearSelection();
      return;
    }

    final hits = DesignerGeometry.entitiesIn(
      selection,
      context.world.query([jge.TransformComponent]),
      pickable: context.controller.isPickable,
    );

    if (hits.isEmpty && _additiveBase.isEmpty) {
      sceneState.clearSelection();
      return;
    }

    // Re-apply the pre-existing selection first so Ctrl+sweep is additive.
    for (final id in _additiveBase) {
      final entity = context.world.getEntity(id);
      if (entity != null && !sceneState.isInMultiSelection(id)) {
        sceneState.toggleMultiSelect(entity);
      }
    }
    for (final entity in hits) {
      if (!sceneState.isInMultiSelection(entity.id)) {
        sceneState.toggleMultiSelect(entity);
      }
    }

    context.controller.setStatus('${hits.length} selected');
  }

  // ── Duplicate ─────────────────────────────────────────────────────────────

  List<jge.Entity> _duplicate(jge.World world, List<jge.Entity> entities) => [
    for (final entity in entities)
      () {
        final copy = world.createEntityWithComponents(
          EntitySpec.of(entity, codec).decode(),
          name: _uniqueName(_baseName(entity.name)),
        );
        sceneState.registerEntity(copy);
        return copy;
      }(),
  ];

  void _discardCopies() {
    for (final copy in _targets) {
      if (!copy.isAlive) continue;
      sceneState.removeEntityNode(copy.id);
      _world?.destroyEntity(copy);
    }
    _select(_originalSelection);
  }

  static String _baseName(String? name) =>
      (name ?? 'Entity').replaceFirst(RegExp(r'_\d+$'), '');

  void _select(List<jge.Entity> entities) {
    sceneState.clearSelection();
    if (entities.length == 1) {
      sceneState.selectEntity(entities.single);
      return;
    }
    for (final entity in entities) {
      sceneState.toggleMultiSelect(entity);
    }
  }

  // ── Picking ───────────────────────────────────────────────────────────────

  /// The entities the current selection covers, primary plus multi-selection.
  /// What this tool can move: what is selected, less anything that is not
  /// in the world.
  ///
  /// A piece of interface is selected from the scene tree like anything
  /// else, but it has no transform — it is placed by its slot, and moved
  /// in the UI mode. Handing one to a tool that reads transforms is how a
  /// pointer move in the viewport ended in a null check.
  List<jge.Entity> _selectionEntities(jge.World world) {
    final ids = sceneState.multiSelectedIds.value;
    if (ids.isNotEmpty) {
      return ids
          .map(world.getEntity)
          .whereType<jge.Entity>()
          .where((e) => e.isActive && _isInTheWorld(e))
          .toList();
    }
    final selected = sceneState.selectedEntity.value;
    return selected == null || !_isInTheWorld(selected) ? const [] : [selected];
  }

  static bool _isInTheWorld(jge.Entity entity) =>
      entity.getComponent<jge.TransformComponent>() != null;

  /// Combined bounds of [entities]; a sizeless marker counts as a point.
  static Rect? _groupBounds(List<jge.Entity> entities) {
    Rect? union;
    for (final entity in entities) {
      var bounds = DesignerGeometry.worldBounds(entity);
      if (bounds == null) {
        final t = entity.getComponent<jge.TransformComponent>();
        if (t == null) continue;
        bounds = Rect.fromLTWH(t.position.x, t.position.y, 0, 0);
      }
      union = union == null ? bounds : union.expandToInclude(bounds);
    }
    return union;
  }

  /// Topmost pickable entity under the pointer.
  jge.Entity? _entityAt(ToolContext context) => DesignerGeometry.topmostAt(
    context.world,
    context.worldPosition,
    pickable: context.controller.isPickable,
    markerReach: context.pixels(12),
  );
}
