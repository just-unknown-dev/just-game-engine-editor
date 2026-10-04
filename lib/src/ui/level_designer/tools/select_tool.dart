import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/level_map/level_map_documents.dart';
import '../../../core/level_map/tile_commands.dart';
import '../../../core/level_map/tile_turn.dart';
import '../../../core/state/editor_scene_state.dart';
import '../../../core/state/transform_mode.dart';
import '../../overlay/gizmo_painter.dart' show GizmoHandle;
import '../../overlay/transform_gizmo.dart';
import '../state/component_resizer.dart';
import '../state/designer_geometry.dart';
import '../../../core/entity/hierarchy_commands.dart';
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
/// - Press an entity: select it; drag to move the whole selection. Alt at the start of the drag moves a copy instead.
/// - The selection shows one gizmo, as the Move, Scale and Rotate toolbar
///   says (W, E, R):
///   - Move: drag an arrow to move along it, the square to move freely.
///   - Scale: drag one of the eight handles on the selection's bounds to
///     resize every selected thing in proportion. Shift keeps the aspect
///     ratio, Alt resizes about the centre.
///   - Rotate: drag the ring to turn about the selection's centre, in 15
///     degree steps. A piece of a map turns its tiles, a quarter at a time.
///   - All (Q), where it starts: the resize handles and the knob above the
///     bounds that turns it, together.
/// - Double-click open ground: the Level Map.
///
/// Moving or turning a parent takes what is under it along.
///
/// While dragging, edges and centres snap to other entities and ruler
/// guides, then to the grid. Hold Ctrl to place freely.
class SelectTool extends LevelToolHandler {
  SelectTool({
    required this.sceneState,
    required this.history,
    required this.codec,
    this.layout = const SelectionHandleLayout(),
    this.mapDocs,
    this.rotationStep,
    String Function(String prefix)? uniqueName,
  }) : _uniqueName = uniqueName ?? ((prefix) => prefix);

  /// The step a snapped turn moves in, in radians, read as the turn is
  /// made: the settings' step. Without it, [layout]'s.
  final double Function()? rotationStep;

  /// The maps being edited, for turning a piece of one's tiles. Without
  /// them a piece does not turn.
  final LevelMapDocuments? mapDocs;

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

  /// None of its own: the transform toolbar's All, Move, Scale and Rotate
  /// (Q, W, E, R) are this tool, each with its gizmo.
  @override
  String? get shortcut => null;

  @override
  String? get description =>
      'Marquee on empty space; drag to move, Alt+drag to copy. The '
      'selection shows the Move (W), Scale (E) or Rotate (R) gizmo';

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

  // What is under the targets, moved and turned with them, and where it was.
  List<jge.Entity> _carried = const [];
  List<TransformSnapshot> _carriedBefore = const [];
  List<Rect> _snapRects = const [];
  List<double> _guideXs = const [];
  List<double> _guideYs = const [];

  // Resize.
  ResizeHandle? _handle;
  List<EntitySpec> _beforeSpecs = const [];

  // Move along one axis: an arrow of the move gizmo.
  Axis? _axis;

  /// Whether the rotate gesture began on the ring, which lies across the
  /// level round the selection: a click on it that turns nothing is a
  /// click on whatever is under it.
  bool _onRing = false;

  /// Set while a click that fell through the ring is replayed.
  bool _throughGizmo = false;

  // Rotate.
  double _startAngle = 0;

  // Turning a piece of a map: its tiles, a step at a time.
  LevelMapTarget? _piece;
  List<(jge.MapLayerData, Set<jge.TileCoord>)> _pieceLayers = const [];
  jge.TileCoord? _piecePivot;
  List<TileStroke> _pieceStrokes = const [];
  int _pieceSteps = 0;

  // Alt+drag duplicate.
  jge.World? _world;
  bool _duplicating = false;
  List<jge.Entity> _originalSelection = const [];

  @override
  bool onPointerDown(ToolContext context) {
    _world = context.world;
    final selection = _selectionEntities(context.world);
    final bounds = _groupBounds(selection);

    // The gizmo first: it sits on top of the selection it belongs to.
    if (bounds != null &&
        !context.isCtrlDown &&
        !_throughGizmo &&
        _onGizmo(context, selection, bounds)) {
      return true;
    }

    final hit = _entityAt(context);
    if (hit == null) {
      if (context.isDoubleClick && !context.isCtrlDown) {
        // A double-click on open ground: the Level Map, whose ground it is.
        final map = jge.LevelMaps.primaryEntity(context.world);
        if (map != null) {
          sceneState.selectEntity(map);
          context.controller.setStatus('${map.name ?? 'The map'} selected');
          return true;
        }
      }
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

    // Pressing what is not part of the current selection replaces the
    // selection; pressing what *is* keeps it, so a multi-selection can be
    // dragged as a unit rather than collapsing to whatever was grabbed.
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

  /// The mode the selection's gizmo is in: the toolbar's, when the
  /// selection can take it.
  static TransformMode? shownMode(
    ToolContext context,
    List<jge.Entity> selection,
  ) => TransformModes.shown(
    context.controller.view.transformMode.value,
    TransformModes.forEntities(context.world, selection),
  );

  /// Starts what a press on [selection]'s gizmo means, when it is on it.
  bool _onGizmo(ToolContext context, List<jge.Entity> selection, Rect bounds) {
    final at = context.worldPosition;
    final px = context.unitsPerPixel;
    switch (shownMode(context, selection)) {
      case TransformMode.all:
        // As it always was: the knob above the bounds turns, the handles on
        // them resize, and the body moves — what the selection can take.
        final available = TransformModes.forEntities(context.world, selection);
        final knob = layout.rotateKnobAt(bounds, px);
        if (available.contains(TransformMode.rotate) &&
            (at - knob).distance <= context.pixels(layout.handlePixels) * 1.5) {
          _startRotate(context, selection, bounds);
          return true;
        }
        return available.contains(TransformMode.scale) &&
            _startResize(context, selection, bounds);
      case TransformMode.move:
        final handle = TransformGizmo.moveHandleAt(at, bounds.center, px: px);
        if (handle == GizmoHandle.none) return false;
        var targets = selection;
        if (context.isAltDown) {
          _originalSelection = targets;
          targets = _duplicate(context.world, targets);
          _select(targets);
          _duplicating = true;
        }
        _begin(
          context,
          targets,
          _groupBounds(targets) ?? bounds,
          _Gesture.move,
        );
        _axis = switch (handle) {
          GizmoHandle.translateX => Axis.horizontal,
          GizmoHandle.translateY => Axis.vertical,
          _ => null,
        };
        return true;
      case TransformMode.scale:
        return _startResize(context, selection, bounds);
      case TransformMode.rotate:
        final radius = layout.ringRadius(bounds, px);
        if (!TransformGizmo.onRing(at, bounds.center, radius, px: px)) {
          return false;
        }
        _startRotate(context, selection, bounds);
        _onRing = true;
        return true;
      case null:
        return false;
    }
  }

  /// Starts a resize when the press is on one of the handles on [bounds].
  bool _startResize(
    ToolContext context,
    List<jge.Entity> selection,
    Rect bounds,
  ) {
    // A point marker has nothing to resize.
    if (bounds.width <= 0 || bounds.height <= 0) return false;
    final reach = context.pixels(layout.handlePixels);
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
    return false;
  }

  /// Starts turning [selection] about the centre of [bounds] — or, for a
  /// lone piece of a map, its tiles.
  void _startRotate(
    ToolContext context,
    List<jge.Entity> selection,
    Rect bounds,
  ) {
    _begin(context, selection, bounds, _Gesture.rotate);
    _startAngle = _angleFrom(bounds.center, context.worldPosition);
    if (selection.length == 1 &&
        jge.LevelMaps.isPiece(context.world, selection.single)) {
      _holdPiece(selection.single);
    }
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
    final turned = _piece == null ? _anyTransformChanged() : _pieceSteps != 0;
    if (_gesture == _Gesture.rotate && _onRing && !turned) {
      // A click on the ring, not a turn: what the click would have done
      // without it there — pick what is under it, or nothing.
      onCancel();
      _throughGizmo = true;
      onPointerDown(context);
      _throughGizmo = false;
      onPointerUp(context);
      return;
    }
    switch (_gesture) {
      case _Gesture.marquee:
        _commitMarquee(context, _marqueeStart!);
      case _Gesture.move:
        _commitMove(context);
      case _Gesture.resize:
        _commitResize(context);
      case _Gesture.rotate:
        _piece == null ? _commitTransform('Rotate') : _commitPieceTurn();
      case _Gesture.none:
        break;
    }
    _reset(context);
  }

  @override
  void onCancel() {
    // Put everything back: an abandoned gesture must not leave a half-applied
    // edit behind.
    for (final stroke in _pieceStrokes.reversed) {
      stroke.revert();
    }
    for (var i = 0; i < _carried.length; i++) {
      if (_carried[i].isAlive) _carriedBefore[i].applyTo(_carried[i]);
    }
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
    // A resize changes each target's own size; moving and turning take
    // what is under them along.
    _carried = gesture == _Gesture.resize
        ? const []
        : carriedWith(targets, world: context.world);
    _carriedBefore = _carried.map(TransformSnapshot.of).toList(growable: false);

    // What the selection can snap to, fixed for the gesture: everything
    // visible and pickable except what moves.
    final moving = {
      for (final e in [...targets, ..._carried]) e.id,
    };
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
    _carried = const [];
    _carriedBefore = const [];
    _beforeSpecs = const [];
    _snapRects = const [];
    _handle = null;
    _axis = null;
    _onRing = false;
    _piece = null;
    _pieceLayers = const [];
    _piecePivot = null;
    _pieceStrokes = const [];
    _pieceSteps = 0;
    _duplicating = false;
    _originalSelection = const [];
  }

  // ── Move ──────────────────────────────────────────────────────────────────

  void _move(ToolContext context) {
    var delta = context.worldPosition - _origin;
    var snapX = true;
    var snapY = true;
    // An arrow of the move gizmo holds the drag to its axis; otherwise Shift
    // constrains to the dominant axis — the standard way to keep a row of
    // platforms aligned while sliding it.
    if (_axis == Axis.horizontal) {
      delta = Offset(delta.dx, 0);
      snapY = false;
    } else if (_axis == Axis.vertical) {
      delta = Offset(0, delta.dy);
      snapX = false;
    } else if (context.isShiftDown) {
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
    for (var i = 0; i < _carried.length; i++) {
      final entity = _carried[i];
      if (!entity.isAlive) continue;
      entity.getComponent<jge.TransformComponent>()?.setPositionXY(
        _carriedBefore[i].x + moved.dx,
        _carriedBefore[i].y + moved.dy,
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
            gridSize: context.moveStep,
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
      onCancel();
      return;
    }
    final copies = _targets;
    final label = copies.length == 1
        ? 'Duplicate ${_originalSelection.first.name ?? 'entity'}'
        : 'Duplicate ${copies.length} entities';
    _push(label, [
      CreateEntitiesCommand.adopting(
        codec: codec,
        label: label,
        world: context.world,
        sceneState: sceneState,
        entities: copies,
        onCreated: _select,
      ),
    ]);
  }

  /// Records a move or rotation as one undo step, if anything changed.
  void _commitTransform(String verb) {
    final label = _label(verb);
    _push(label, [
      if (_targets.isNotEmpty && _anyTransformChanged())
        TransformCommand(
          label: label,
          entities: [..._targets, ..._carried],
          before: [..._before, ..._carriedBefore],
          after: [
            for (final e in [..._targets, ..._carried]) TransformSnapshot.of(e),
          ],
          sceneState: sceneState,
        ),
    ]);
  }

  /// One undo step of [commands]: one gesture.
  void _push(String label, List<EditorCommand> commands) {
    if (commands.isEmpty) return;
    history.pushApplied(
      commands.length == 1
          ? commands.single
          : CompositeCommand(label: label, commands: commands),
    );
    sceneState.markDirty();
  }

  String _label(String verb) => _targets.length == 1
      ? '$verb ${_targets.single.name ?? 'entity'}'
      : '$verb ${_targets.length} entities';

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
    final label = _label('Resize');
    final entities = EntityStateCommand(
      label: label,
      world: context.world,
      sceneState: sceneState,
      ids: [for (final e in _targets) e.id],
      before: _beforeSpecs,
      after: [for (final e in _targets) EntitySpec.of(e, codec)],
    );
    _push(label, [
      if (_targets.isNotEmpty && entities.changesAnything) entities,
    ]);
  }

  // ── Rotate ────────────────────────────────────────────────────────────────

  void _rotate(ToolContext context) {
    final pivot = _startBounds.center;
    var angle = _angleFrom(pivot, context.worldPosition) - _startAngle;
    if (_piece != null) {
      _turnPiece(context, angle);
      return;
    }
    if (context.snapping) {
      final step = rotationStep?.call() ?? layout.rotationStep;
      if (step > 0) angle = (angle / step).roundToDouble() * step;
    }
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    Offset turn(Offset p) {
      final dx = p.dx - pivot.dx;
      final dy = p.dy - pivot.dy;
      return Offset(
        pivot.dx + dx * cos - dy * sin,
        pivot.dy + dx * sin + dy * cos,
      );
    }

    void turnEntity(jge.Entity entity, TransformSnapshot before) {
      if (!entity.isAlive) return;
      final to = turn(Offset(before.x, before.y));
      entity.getComponent<jge.TransformComponent>()
        ?..setPositionXY(to.dx, to.dy)
        ..angle = before.angle + angle;
      sceneState.syncEntityNode(entity);
    }

    for (var i = 0; i < _targets.length; i++) {
      turnEntity(_targets[i], _before[i]);
    }
    for (var i = 0; i < _carried.length; i++) {
      turnEntity(_carried[i], _carriedBefore[i]);
    }
    sceneState.refresh();
    context.controller.setStatus('${(angle * 180 / math.pi).round()}°');
  }

  // ── Turning a piece of a map ──────────────────────────────────────────────

  /// Readies [piece] to turn. A map follows its position and nothing else,
  /// so turning one means turning its tiles.
  void _holdPiece(jge.Entity piece) {
    final target = mapDocs?.resolve(piece);
    if (target == null || target.isReadOnly) return;
    final layers = [
      for (final layer in target.data.layers)
        (
          layer,
          {for (final (x, y, _) in layer.cells.cells) jge.TileCoord(x, y)},
        ),
    ];
    final all = {for (final (_, cells) in layers) ...cells};
    if (all.isEmpty) return;
    _piece = target;
    _pieceLayers = layers;
    _piecePivot = TileTurn.pivotOf(target.geometry, all);
  }

  /// Turns the piece's tiles the whole steps [angle] comes to, from where
  /// they started.
  void _turnPiece(ToolContext context, double angle) {
    final target = _piece!;
    final g = target.geometry;
    final steps = (angle / TileTurn.stepAngle(g)).round();
    if (steps == _pieceSteps) return;
    for (final stroke in _pieceStrokes.reversed) {
      stroke.revert();
    }
    _pieceSteps = steps;
    _pieceStrokes = [
      for (final (layer, _) in _pieceLayers)
        TileStroke(docs: mapDocs!, ref: target.ref, layer: layer),
    ];
    for (var i = 0; i < _pieceLayers.length; i++) {
      TileTurn.turn(
        _pieceStrokes[i],
        g,
        _pieceLayers[i].$2,
        steps,
        pivot: _piecePivot,
      );
    }
    context.controller.setStatus(
      '${(steps * TileTurn.stepAngle(g) * 180 / math.pi).round()}°',
    );
  }

  void _commitPieceTurn() {
    final label = _label('Rotate');
    _push(label, [for (final stroke in _pieceStrokes) ?stroke.finish(label)]);
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
      if (_additiveBase.isEmpty) {
        sceneState.clearSelection();
      }
      return;
    }

    // A sweep takes what is on the level's map, never the map itself: it is
    // under everything, and moving it moves all of it. A click, a
    // double-click on its ground or the tree picks it.
    final hits =
        DesignerGeometry.entitiesIn(
          selection,
          context.world.query([jge.TransformComponent]),
          pickable: context.controller.isPickable,
        )..removeWhere(
          (e) =>
              e.hasComponent<jge.LevelMapComponent>() &&
              !jge.LevelMaps.isPiece(context.world, e),
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

  /// Copies of [entities], each just after its original under the same
  /// parent.
  List<jge.Entity> _duplicate(jge.World world, List<jge.Entity> entities) => [
    for (final entity in entities)
      () {
        final copy = world.createEntityWithComponents([
          for (final c in EntitySpec.of(entity, codec).decode())
            if (c is! jge.ParentComponent && c is! jge.ChildrenComponent) c,
        ], name: _uniqueName(_baseName(entity.name)));
        sceneState.registerEntity(copy);
        final at = HierarchySlot.of(
          entity,
          world: world,
          sceneState: sceneState,
        );
        if (at.parentId != null) {
          placeEntity(
            copy,
            world: world,
            sceneState: sceneState,
            slot: HierarchySlot(parentId: at.parentId, index: at.index + 1),
          );
        }
        return copy;
      }(),
  ];

  void _discardCopies() {
    final world = _world;
    for (final copy in _targets) {
      if (!copy.isAlive || world == null) continue;
      detachEntity(copy, world: world, sceneState: sceneState);
      sceneState.removeEntityNode(copy.id);
      world.destroyEntity(copy, withChildren: false);
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
  Rect? _groupBounds(List<jge.Entity> entities) {
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
