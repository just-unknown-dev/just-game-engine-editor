/// What the UI mode is showing, and what it knows about where things
/// landed.
///
/// The interface is laid out by Flutter, so the editor cannot work out
/// where a node is by itself — it reads back the boxes the real widgets
/// were given. That is what makes the mode what-you-see-is-what-you-get
/// rather than a second, slightly different, drawing of the same scene.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'ui_device.dart';

class UiModeSession {
  UiModeSession({required jge.World Function() world}) : _world = world;

  final jge.World Function() _world;

  /// The world being edited. Read on use: the engine's world does not
  /// exist until it initialises, and the overlay is built before that.
  jge.World get world => _world();

  /// Whether the viewport is showing the interface rather than the world.
  final Signal<bool> enabled = Signal(false, debugLabel: 'uiMode');

  /// The screen the canvas is being checked against.
  final Signal<UiDevice> device = Signal(
    UiDevices.phone,
    debugLabel: 'uiDevice',
  );

  /// Whether that screen is turned on its side.
  final Signal<bool> landscape = Signal(false, debugLabel: 'uiLandscape');

  /// Whether to draw each node's box, whether or not it is selected.
  final Signal<bool> showBoxes = Signal(false, debugLabel: 'uiBoxes');

  /// Whether a drag lands on a sibling's edge or the middle of the parent.
  final Signal<bool> snap = Signal(true, debugLabel: 'uiSnap');

  /// Where each node landed, filled in by the layer as it builds.
  final Map<int, GlobalKey> nodeKeys = {};

  /// The screen's size, the way round it is being held.
  Size get frameSize => landscape.value
      ? Size(device.value.height, device.value.width)
      : Size(device.value.width, device.value.height);

  void dispose() {
    enabled.dispose();
    device.dispose();
    landscape.dispose();
    showBoxes.dispose();
    snap.dispose();
  }

  /// Where [entity] is on screen, or null when it is not drawn.
  Rect? rectOf(jge.Entity entity, {required RenderBox against}) {
    final context = nodeKeys[entity.id]?.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: against);
    return topLeft & box.size;
  }

  /// The deepest node under [point], which is the one a click means.
  ///
  /// Depth first and last-child first, so what is drawn on top is what is
  /// picked — the same order the eye picks it.
  jge.Entity? pick(Offset point, {required RenderBox against}) {
    jge.Entity? found;
    for (final canvas in _canvases) {
      final hit = _pickUnder(canvas, point, against);
      if (hit != null) found = hit;
    }
    return found;
  }

  jge.Entity? _pickUnder(jge.Entity entity, Offset point, RenderBox against) {
    // Children first: the last one drawn is on top.
    for (final child in _childrenOf(entity).reversed) {
      final hit = _pickUnder(child, point, against);
      if (hit != null) return hit;
    }
    final rect = rectOf(entity, against: against);
    if (rect == null || !rect.contains(point)) return null;
    // A canvas fills the screen; picking it by its own box would mean
    // never picking anything else.
    return entity.getComponent<jge.UiCanvasComponent>() == null ? entity : null;
  }

  /// The canvases being shown, lowest first.
  List<jge.Entity> get _canvases {
    final found =
        [
          for (final e in world.query([jge.UiCanvasComponent]))
            if (e.isActive && e.getComponent<jge.UiCanvasComponent>()!.visible)
              e,
        ]..sort(
          (a, b) => a
              .getComponent<jge.UiCanvasComponent>()!
              .sortOrder
              .compareTo(b.getComponent<jge.UiCanvasComponent>()!.sortOrder),
        );
    return found;
  }

  List<jge.Entity> _childrenOf(jge.Entity entity) {
    final children = entity.getComponent<jge.ChildrenComponent>();
    if (children == null) return const [];
    return [
      for (final id in children.childIds)
        if (world.getEntity(id) case final child?)
          if (child.isActive) child,
    ];
  }

  /// The boxes of everything except [except] and what is under it — what a
  /// drag snaps to.
  List<Rect> snapTargets(jge.Entity? except, {required RenderBox against}) {
    final skip = <int>{};
    if (except != null) {
      skip.add(except.id);
      void mark(jge.Entity e) {
        for (final child in _childrenOf(e)) {
          skip.add(child.id);
          mark(child);
        }
      }

      mark(except);
    }
    final out = <Rect>[];
    void walk(jge.Entity entity) {
      if (!skip.contains(entity.id)) {
        final rect = rectOf(entity, against: against);
        if (rect != null) out.add(rect);
      }
      for (final child in _childrenOf(entity)) {
        walk(child);
      }
    }

    for (final canvas in _canvases) {
      walk(canvas);
    }
    return out;
  }
}

/// How far a drag may be from an edge and still land on it.
const double kUiSnapDistance = 6;

/// [offset] pulled onto the nearest edge of [targets], and the lines that
/// were snapped to so the viewport can draw them.
({Offset offset, List<Rect> lines}) snapUiDrag({
  required Rect moving,
  required Offset offset,
  required List<Rect> targets,
}) {
  var dx = offset.dx;
  var dy = offset.dy;
  final lines = <Rect>[];
  final moved = moving.shift(offset);

  double? bestX;
  double? bestY;
  var gapX = kUiSnapDistance;
  var gapY = kUiSnapDistance;
  Rect? lineX;
  Rect? lineY;

  for (final target in targets) {
    for (final (from, to) in [
      (moved.left, target.left),
      (moved.left, target.right),
      (moved.right, target.right),
      (moved.right, target.left),
      (moved.center.dx, target.center.dx),
    ]) {
      final gap = (from - to).abs();
      if (gap < gapX) {
        gapX = gap;
        bestX = dx + (to - from);
        lineX = target;
      }
    }
    for (final (from, to) in [
      (moved.top, target.top),
      (moved.top, target.bottom),
      (moved.bottom, target.bottom),
      (moved.bottom, target.top),
      (moved.center.dy, target.center.dy),
    ]) {
      final gap = (from - to).abs();
      if (gap < gapY) {
        gapY = gap;
        bestY = dy + (to - from);
        lineY = target;
      }
    }
  }

  if (bestX != null) {
    dx = bestX;
    if (lineX != null) lines.add(lineX);
  }
  if (bestY != null) {
    dy = bestY;
    if (lineY != null && lineY != lineX) lines.add(lineY);
  }
  return (offset: Offset(dx, dy), lines: lines);
}
