import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/state/transform_mode.dart';
import '../level_designer/grid/square_grid.dart';
import '../level_designer/state/designer_geometry.dart';
import 'transform_gizmo.dart';
import '../../core/theme/viewport_look.dart';
import '../../core/view/editor_view.dart';

/// Gizmo handle identifier returned by [GizmoHitTester.hitTest].
enum GizmoHandle {
  none(GizmoOp.none, 0),
  translateXY(GizmoOp.translate, GizmoAxes.x | GizmoAxes.y),
  translateX(GizmoOp.translate, GizmoAxes.x),
  translateY(GizmoOp.translate, GizmoAxes.y),
  rotate(GizmoOp.rotate, GizmoAxes.z),
  scaleNW(GizmoOp.scale, GizmoAxes.x | GizmoAxes.y),
  scaleNE(GizmoOp.scale, GizmoAxes.x | GizmoAxes.y),
  scaleSE(GizmoOp.scale, GizmoAxes.x | GizmoAxes.y),
  scaleSW(GizmoOp.scale, GizmoAxes.x | GizmoAxes.y),
  scaleX(GizmoOp.scale, GizmoAxes.x),
  scaleY(GizmoOp.scale, GizmoAxes.y),
  body(GizmoOp.translate, GizmoAxes.x | GizmoAxes.y),

  // A 3-D gizmo's own handles. Nothing in 2-D produces them.
  translateZ(GizmoOp.translate, GizmoAxes.z),
  rotateX(GizmoOp.rotate, GizmoAxes.x),
  rotateY(GizmoOp.rotate, GizmoAxes.y),
  scaleZ(GizmoOp.scale, GizmoAxes.z);

  const GizmoHandle(this.op, this.axes);

  /// What dragging it does.
  final GizmoOp op;

  /// Which axes it works along ([GizmoAxes] bits): a move handle's
  /// directions, a turn handle's axis of rotation.
  final int axes;

  /// Whether it works along [axis] (one of the [GizmoAxes] bits).
  bool uses(int axis) => axes & axis != 0;
}

/// What a gizmo handle does.
enum GizmoOp { none, translate, rotate, scale }

/// Axis bits for [GizmoHandle.axes].
abstract final class GizmoAxes {
  static const int x = 1, y = 2, z = 4;
}

/// Result of a [GizmoHitTester.hitTest] call.
class GizmoHitResult {
  const GizmoHitResult(this.handle, this.entity);

  final GizmoHandle handle;
  final Entity? entity;

  bool get isNone => handle == GizmoHandle.none;
}

/// Paints editor gizmos (translate arrows, rotation arc, scale handles,
/// selection outline) onto the game canvas.
///
/// All drawing is done in **screen space** — call [worldToScreen] on world
/// positions before passing them.  The canvas received by
/// [JustGameEditorPlugin.onRender] is in screen space (parallax / background
/// layer, before the camera transform).
class GizmoPainter {
  /// The unscaled size the gizmo draws [component] at, or null. Through the
  /// extent on its definition first, so it is the marquee's answer too.
  ///
  /// [definitions] defaults to the engine's own.
  static Size? sizeOf(
    Component component, [
    ComponentDefinitionRegistry? definitions,
  ]) => _sizeFromComponent(
    component,
    definitions ?? DesignerGeometry.definitionsFor(null),
  );

  static double get _rotRadius =>
      GizmoConstants.rotRadius * ViewportLook.gizmoScale;
  static Color get _colSel => ViewportLook.selection;
  static const Color _colOrigin = GizmoConstants.colOrigin;

  final Paint _paint = Paint()..isAntiAlias = true;

  /// The square grid. The plugin draws whichever topology the scope has;
  /// this stays for callers that only ever wanted squares.
  void paintInfiniteGrid(
    Canvas canvas,
    EditorView camera,
    Size canvasSize, {
    required double gridSize,
  }) => const SquareGrid().paintGrid(
    canvas,
    camera,
    canvasSize,
    cellSize: gridSize,
  );

  /// Paints [mode]'s gizmo for [entity] using [camera] to convert
  /// positions: all of them in one, arrows to move it, handles to scale it,
  /// or a ring to turn it — as the toolbar says. [allows] is what [entity]
  /// can take; All leaves the rest off.
  ///
  /// [canvasSize] is the full viewport size.
  void paintGizmos(
    Canvas canvas,
    Entity entity,
    EditorView camera,
    Size canvasSize, {
    TransformMode mode = TransformMode.all,
    Set<TransformMode>? allows,
  }) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;

    camera.viewportSize = canvasSize;
    final screenPos = camera.worldToScreen(transform.position.toOffset());

    final bounds = _computeScreenBounds(entity, transform, camera);

    // Selection outline
    _paintSelectionRect(canvas, bounds.corners);

    switch (mode) {
      case TransformMode.all:
        TransformGizmo.paintAll(
          canvas,
          screenPos,
          corners: bounds.corners,
          rotation: transform.angle,
          scale: allows?.contains(TransformMode.scale) ?? true,
          rotate: allows?.contains(TransformMode.rotate) ?? true,
        );
      case TransformMode.move:
        TransformGizmo.paintMove(canvas, screenPos);
      case TransformMode.scale:
        TransformGizmo.paintScaleAxes(canvas, screenPos);
        TransformGizmo.paintScaleCorners(canvas, bounds.corners);
      case TransformMode.rotate:
        TransformGizmo.paintRotate(
          canvas,
          screenPos,
          _rotRadius,
          angle: transform.angle,
        );
    }

    // Origin dot
    _paint
      ..style = PaintingStyle.fill
      ..color = _colOrigin;
    canvas.drawCircle(screenPos, 3.5, _paint);
  }

  /// Draws a small camera icon at every camera entity's position, regardless
  /// of selection, so it's discoverable at a glance while editing.
  void paintCameraMarkers(
    Canvas canvas,
    List<Entity> cameraEntities,
    EditorView camera,
    Size canvasSize,
  ) {
    if (cameraEntities.isEmpty || canvasSize == Size.zero) return;
    camera.viewportSize = canvasSize;
    for (final entity in cameraEntities) {
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) continue;
      final screenPos = camera.worldToScreen(transform.position.toOffset());
      _paintCameraIcon(canvas, screenPos);
    }
  }

  void _paintCameraIcon(Canvas canvas, Offset center) {
    const iconData = Icons.videocam_rounded;
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF40E0D0).withValues(alpha: 0.18);
    canvas.drawCircle(center, 16, _paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: const Color(0xFF40E0D0),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  /// Draws a small icon + tag label at every spawn point entity's position,
  /// regardless of selection, so spawn points (player, zombie, ...) are
  /// discoverable at a glance while editing.
  void paintSpawnMarkers(
    Canvas canvas,
    List<Entity> spawnPoints,
    EditorView camera,
    Size canvasSize,
  ) {
    if (spawnPoints.isEmpty || canvasSize == Size.zero) return;
    camera.viewportSize = canvasSize;
    for (final entity in spawnPoints) {
      final transform = entity.getComponent<TransformComponent>();
      final spawn = entity.getComponent<SpawnComponent>();
      if (transform == null || spawn == null) continue;
      final screenPos = camera.worldToScreen(transform.position.toOffset());
      _paintSpawnIcon(canvas, screenPos, spawn.spawner);
    }
  }

  void _paintSpawnIcon(Canvas canvas, Offset center, String spawner) {
    const iconData = Icons.person_pin_circle_rounded;
    const accent = Color(0xFFFFB74D);
    _paint
      ..style = PaintingStyle.fill
      ..color = accent.withValues(alpha: 0.18);
    canvas.drawCircle(center, 16, _paint);

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: accent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: spawner,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy + 18),
    );
  }

  /// Rings every one of [entities] in [color] and labels it `#tag` — what
  /// a tag being pointed at means in the level.
  void paintTagHighlight(
    Canvas canvas,
    List<Entity> entities,
    String tag,
    Color color,
    EditorView camera,
    Size canvasSize,
  ) {
    if (entities.isEmpty || canvasSize == Size.zero) return;
    camera.viewportSize = canvasSize;
    final label = TextPainter(
      text: TextSpan(
        text: '#$tag',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    for (final entity in entities) {
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) continue;
      final bounds = _computeScreenBounds(entity, transform, camera);
      final box = Rect.fromCenter(
        center: bounds.center,
        width: math.max(bounds.halfW * 2, 16) + 10,
        height: math.max(bounds.halfH * 2, 16) + 10,
      );
      final shape = RRect.fromRectAndRadius(box, const Radius.circular(4));
      _paint
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.12);
      canvas.drawRRect(shape, _paint);
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color;
      canvas.drawRRect(shape, _paint);
      label.paint(canvas, Offset(box.left, box.top - label.height - 2));
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _paintSelectionRect(Canvas canvas, List<Offset> corners) {
    if (corners.length != 4) return;
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = _colSel.withValues(alpha: 0.7);

    final path = ui.Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(path, _paint);
  }
}

class _ScreenBounds {
  const _ScreenBounds({
    required this.center,
    required this.halfW,
    required this.halfH,
    required this.rotation,
    required this.corners,
  });

  final Offset center;
  final double halfW;
  final double halfH;
  final double rotation;
  final List<Offset> corners;
}

const Size _defaultSelectionSize = GizmoConstants.defaultSelectionSize;

_ScreenBounds _computeScreenBounds(
  Entity entity,
  TransformComponent transform,
  EditorView camera,
) {
  final baseSize = _largestComponentSize(entity);
  final center = camera.worldToScreen(transform.position.toOffset());
  final halfW =
      (baseSize.width / 2) * camera.zoom * transform.scale.x.abs() + 2;
  final halfH =
      (baseSize.height / 2) * camera.zoom * transform.scale.y.abs() + 2;
  final corners = _buildRotatedCorners(center, halfW, halfH, transform.angle);

  return _ScreenBounds(
    center: center,
    halfW: halfW,
    halfH: halfH,
    rotation: transform.angle,
    corners: corners,
  );
}

Size _largestComponentSize(Entity entity) {
  var best = _defaultSelectionSize;
  var bestArea = best.width * best.height;

  void consider(Size? candidate) {
    if (candidate == null) return;
    final w = candidate.width.abs();
    final h = candidate.height.abs();
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return;
    final area = w * h;
    if (area > bestArea) {
      best = Size(w, h);
      bestArea = area;
    }
  }

  final definitions = DesignerGeometry.definitionsFor(entity);
  for (final component in entity.components) {
    consider(_sizeFromComponent(component, definitions));
  }

  return best;
}

Size? _sizeFromComponent(
  Component component,
  ComponentDefinitionRegistry definitions,
) {
  // The extent on the definition first: the same answer the marquee and
  // the resize handles use. The branches below remain for anything that
  // has no definition at all.
  final extent = definitions.definitionFor(component)?.extent;
  if (extent != null) return extent.sizeOf(component);

  if (component is RectangleComponent) {
    final inset = component.strokeWidth * 2;
    return Size(component.width + inset, component.height + inset);
  }
  if (component is CapsuleComponent) {
    final inset = component.strokeWidth * 2;
    return Size(component.width + inset, component.height + inset);
  }
  if (component is CircleComponent) {
    final d = (component.radius + component.strokeWidth) * 2;
    return Size(d, d);
  }
  if (component is PolygonComponent) {
    if (component.vertices.isEmpty) return null;
    final rect = _rectFromOffsets(component.vertices);
    if (rect == null) return null;
    final inset = component.strokeWidth * 2;
    return Size(rect.width + inset, rect.height + inset);
  }
  if (component is LineComponent) {
    final rect = Rect.fromPoints(
      component.start - Offset(component.strokeWidth, component.strokeWidth),
      component.end + Offset(component.strokeWidth, component.strokeWidth),
    );
    return Size(rect.width, rect.height);
  }
  if (component is PhysicsBodyComponent) {
    final rect = component.shape.getBounds(Offset.zero);
    return Size(rect.width, rect.height);
  }
  if (component is RenderableComponent) {
    return _sizeFromRenderable(component.renderable);
  }

  return _sizeFromDynamic(component);
}

Size? _sizeFromRenderable(Renderable renderable) {
  if (renderable is Sprite) {
    final srcW =
        renderable.sourceRect?.width ?? renderable.image?.width.toDouble();
    final srcH =
        renderable.sourceRect?.height ?? renderable.image?.height.toDouble();
    final size =
        renderable.renderSize ??
        ((srcW != null && srcH != null) ? Size(srcW, srcH) : null);
    return size;
  }
  if (renderable is RectangleRenderable) {
    return renderable.size;
  }
  if (renderable is CircleRenderable) {
    final d = renderable.radius * 2;
    return Size(d, d);
  }
  if (renderable is LineRenderable) {
    final rect = Rect.fromPoints(
      Offset.zero,
      renderable.endPoint,
    ).inflate(renderable.width);
    return Size(rect.width, rect.height);
  }
  if (renderable is CustomRenderable) {
    final rect = renderable.getBounds();
    if (rect == null) return null;
    return Size(rect.width, rect.height);
  }

  final rect = renderable.getBounds();
  if (rect == null) return null;
  final sx = renderable.scale.x.abs();
  final sy = renderable.scale.y.abs();
  final width = sx > 0.0001 ? rect.width / sx : rect.width;
  final height = sy > 0.0001 ? rect.height / sy : rect.height;
  return Size(width, height);
}

Size? _sizeFromDynamic(dynamic component) {
  final dyn = component;

  try {
    final size = dyn.size;
    if (size is Size) return size;
  } catch (_) {}

  try {
    final w = dyn.width;
    final h = dyn.height;
    if (w is num && h is num) return Size(w.toDouble(), h.toDouble());
  } catch (_) {}

  try {
    final r = dyn.radius;
    if (r is num) {
      final d = r.toDouble() * 2;
      return Size(d, d);
    }
  } catch (_) {}

  try {
    final shape = dyn.shape;
    final rect = shape.getBounds(Offset.zero);
    if (rect is Rect) return Size(rect.width, rect.height);
  } catch (_) {}

  try {
    final points = dyn.vertices;
    if (points is List<Offset> && points.isNotEmpty) {
      final rect = _rectFromOffsets(points);
      if (rect != null) return Size(rect.width, rect.height);
    }
  } catch (_) {}

  try {
    final start = dyn.start;
    final end = dyn.end;
    if (start is Offset && end is Offset) {
      final rect = Rect.fromPoints(start, end);
      return Size(rect.width, rect.height);
    }
  } catch (_) {}

  return null;
}

Rect? _rectFromOffsets(List<Offset> offsets) {
  if (offsets.isEmpty) return null;
  var minX = offsets.first.dx;
  var maxX = offsets.first.dx;
  var minY = offsets.first.dy;
  var maxY = offsets.first.dy;
  for (final p in offsets.skip(1)) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

List<Offset> _buildRotatedCorners(
  Offset center,
  double halfW,
  double halfH,
  double rotation,
) {
  final locals = <Offset>[
    Offset(-halfW, -halfH),
    Offset(halfW, -halfH),
    Offset(halfW, halfH),
    Offset(-halfW, halfH),
  ];
  return locals.map((p) => center + _rotateOffset(p, rotation)).toList();
}

Offset _rotateOffset(Offset v, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

bool _pointInOrientedRect(Offset point, _ScreenBounds bounds) {
  final local = _rotateOffset(point - bounds.center, -bounds.rotation);
  return local.dx.abs() <= bounds.halfW && local.dy.abs() <= bounds.halfH;
}

/// Hit-tests pointer events against gizmo handles and entity bodies.
class GizmoHitTester {
  static double get _rotRadius =>
      GizmoConstants.rotRadius * ViewportLook.gizmoScale;
  static double get _scaleHandle =>
      GizmoConstants.scaleHandle * ViewportLook.gizmoScale;

  /// Returns the [GizmoHitResult] for [screenPos].
  ///
  /// Tests [mode]'s handles on [selected] first, then falls back to body
  /// hit-test against all [entities] (last-added wins for overlaps).
  GizmoHitResult hitTest(
    Offset screenPos,
    Entity? selected,
    List<Entity> entities,
    EditorView camera,
    Size canvasSize, {
    TransformMode mode = TransformMode.all,
    Set<TransformMode>? allows,
  }) {
    camera.viewportSize = canvasSize;

    if (selected != null && selected.isActive) {
      final result = _hitTestHandles(screenPos, selected, camera, mode, allows);
      if (!result.isNone) return result;
    }

    // Body hit-test (last entity = on top)
    for (final entity in entities.reversed) {
      if (!entity.isActive) continue;
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) continue;

      final bounds = _computeScreenBounds(entity, transform, camera);
      if (_pointInOrientedRect(screenPos, bounds)) {
        return GizmoHitResult(GizmoHandle.body, entity);
      }
    }

    return const GizmoHitResult(GizmoHandle.none, null);
  }

  GizmoHitResult _hitTestHandles(
    Offset pos,
    Entity entity,
    EditorView camera,
    TransformMode mode,
    Set<TransformMode>? allows,
  ) {
    final transform = entity.getComponent<TransformComponent>();
    // A piece of interface is selected from the tree like anything else,
    // but it is nowhere in the world: it has no transform, and the world's
    // gizmo has nothing to take hold of. Before the tree listed UI
    // entities this could not happen; once it could, the null check here
    // threw on every pointer move over the viewport.
    if (transform == null) return const GizmoHitResult(GizmoHandle.none, null);
    final center = camera.worldToScreen(transform.position.toOffset());

    switch (mode) {
      case TransformMode.all:
        final handle = TransformGizmo.allHandleAt(
          pos,
          center,
          corners: _computeScreenBounds(entity, transform, camera).corners,
          rotation: transform.angle,
          scale: allows?.contains(TransformMode.scale) ?? true,
          rotate: allows?.contains(TransformMode.rotate) ?? true,
        );
        return handle == GizmoHandle.none
            ? const GizmoHitResult(GizmoHandle.none, null)
            : GizmoHitResult(handle, entity);
      case TransformMode.move:
        final handle = TransformGizmo.moveHandleAt(pos, center);
        return handle == GizmoHandle.none
            ? const GizmoHitResult(GizmoHandle.none, null)
            : GizmoHitResult(handle, entity);
      case TransformMode.scale:
        final axis = TransformGizmo.scaleAxisAt(pos, center);
        if (axis != GizmoHandle.none) return GizmoHitResult(axis, entity);
        final bounds = _computeScreenBounds(entity, transform, camera);
        final corners = <(Offset, GizmoHandle)>[
          (bounds.corners[0], GizmoHandle.scaleNW),
          (bounds.corners[1], GizmoHandle.scaleNE),
          (bounds.corners[2], GizmoHandle.scaleSE),
          (bounds.corners[3], GizmoHandle.scaleSW),
        ];
        for (final (corner, handle) in corners) {
          if ((pos - corner).distance < _scaleHandle + 4) {
            return GizmoHitResult(handle, entity);
          }
        }
      case TransformMode.rotate:
        if (TransformGizmo.onRing(pos, center, _rotRadius)) {
          return GizmoHitResult(GizmoHandle.rotate, entity);
        }
    }
    return const GizmoHitResult(GizmoHandle.none, null);
  }
}
