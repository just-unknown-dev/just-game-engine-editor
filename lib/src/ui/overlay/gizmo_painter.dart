import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../core/constants/editor_constants.dart';
import '../level_designer/grid/square_grid.dart';

/// Gizmo handle identifier returned by [GizmoHitTester.hitTest].
enum GizmoHandle {
  none,
  translateXY,
  translateX,
  translateY,
  rotate,
  scaleNW,
  scaleNE,
  scaleSE,
  scaleSW,
  scaleX,
  scaleY,
  body,
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
  static Size? sizeOf(Component component) => _sizeFromComponent(component);

  static const double _arrowLength = GizmoConstants.arrowLength;
  static const double _arrowHeadLength = GizmoConstants.arrowHeadLength;
  static const double _arrowHeadWidth = GizmoConstants.arrowHeadWidth;
  static const double _rotRadius = GizmoConstants.rotRadius;
  static const double _rotSweep = GizmoConstants.rotSweep;
  static const double _scaleHandle = GizmoConstants.scaleHandle;
  static const double _dotRadius = GizmoConstants.dotRadius;
  static const double _moveHandleRadius = GizmoConstants.moveHandleRadius;
  // Axis-scale square: sits on the arrow shaft before the arrowhead
  static const double _axisSquareOffset = GizmoConstants.axisSquareOffset;
  static const double _axisSquareHalf = GizmoConstants.axisSquareHalf;

  // Colours
  static const Color _colX = GizmoConstants.colX;
  static const Color _colY = GizmoConstants.colY;
  static const Color _colRot = GizmoConstants.colRot;
  static const Color _colScale = GizmoConstants.colScale;
  static const Color _colSel = GizmoConstants.colSel;
  static const Color _colOrigin = GizmoConstants.colOrigin;
  static const Color _colMove = GizmoConstants.colMove;

  final Paint _paint = Paint()..isAntiAlias = true;

  /// The square grid. The plugin draws whichever topology the scope has;
  /// this stays for callers that only ever wanted squares.
  void paintInfiniteGrid(
    Canvas canvas,
    Camera camera,
    Size canvasSize, {
    required double gridSize,
  }) => const SquareGrid().paintGrid(
    canvas,
    camera,
    canvasSize,
    cellSize: gridSize,
  );

  /// Paints gizmos for [entity] using [camera] to convert positions.
  ///
  /// [canvasSize] is the full viewport size.
  void paintGizmos(
    Canvas canvas,
    Entity entity,
    Camera camera,
    Size canvasSize,
  ) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;

    camera.viewportSize = canvasSize;
    final screenPos = camera.worldToScreen(transform.position.toOffset());

    final bounds = _computeScreenBounds(entity, transform, camera);

    // Selection outline
    _paintSelectionRect(canvas, bounds.corners);

    // Translate arrows
    _paintArrow(
      canvas,
      screenPos,
      screenPos + const Offset(_arrowLength, 0),
      _colX,
    );
    _paintArrow(
      canvas,
      screenPos,
      screenPos + const Offset(0, -_arrowLength),
      _colY,
    );

    // Axis-scale squares on the arrow shaft (resize width / height)
    _paintAxisSquare(
      canvas,
      screenPos + const Offset(_axisSquareOffset, 0),
      _colX,
    );
    _paintAxisSquare(
      canvas,
      screenPos + const Offset(0, -_axisSquareOffset),
      _colY,
    );

    // Rotation arc
    _paintRotationArc(canvas, screenPos, transform.rotation);

    // Free-move center handle (drag in both X and Y)
    _paintMoveHandle(canvas, screenPos);

    // Scale handles at oriented bounds corners.
    for (final corner in bounds.corners) {
      _paint
        ..style = PaintingStyle.fill
        ..color = _colScale;
      canvas.drawRect(
        Rect.fromCenter(
          center: corner,
          width: _scaleHandle * 2,
          height: _scaleHandle * 2,
        ),
        _paint,
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
    Camera camera,
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
    Camera camera,
    Size canvasSize,
  ) {
    if (spawnPoints.isEmpty || canvasSize == Size.zero) return;
    camera.viewportSize = canvasSize;
    for (final entity in spawnPoints) {
      final transform = entity.getComponent<TransformComponent>();
      final spawn = entity.getComponent<SpawnComponent>();
      if (transform == null || spawn == null) continue;
      final screenPos = camera.worldToScreen(transform.position.toOffset());
      _paintSpawnIcon(canvas, screenPos, spawn.tag);
    }
  }

  void _paintSpawnIcon(Canvas canvas, Offset center, String tag) {
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
        text: tag,
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

  // ── Private helpers ───────────────────────────────────────────────────────

  void _paintAxisSquare(Canvas canvas, Offset center, Color color) {
    // Filled square
    _paint
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: _axisSquareHalf * 2,
        height: _axisSquareHalf * 2,
      ),
      _paint,
    );
    // Dark border so it pops over the arrow line
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF000000).withValues(alpha: 0.4);
    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: _axisSquareHalf * 2,
        height: _axisSquareHalf * 2,
      ),
      _paint,
    );
  }

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

  void _paintArrow(Canvas canvas, Offset from, Offset to, Color color) {
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color;
    canvas.drawLine(from, to, _paint);

    // Arrowhead
    final dir = (to - from);
    final length = dir.distance;
    if (length == 0) return;
    final norm = dir / length;
    final perp = Offset(-norm.dy, norm.dx);

    final tip = to;
    final base = to - norm * _arrowHeadLength;
    final left = base + perp * (_arrowHeadWidth / 2);
    final right = base - perp * (_arrowHeadWidth / 2);

    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    _paint
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawPath(path, _paint);
  }

  void _paintRotationArc(Canvas canvas, Offset center, double currentRotation) {
    final rect = Rect.fromCircle(center: center, radius: _rotRadius);

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = _colRot.withValues(alpha: 0.6);
    canvas.drawArc(rect, currentRotation, _rotSweep, false, _paint);

    // Dot at arc end
    final arcEnd = Offset(
      center.dx + _rotRadius * math.cos(currentRotation + _rotSweep),
      center.dy + _rotRadius * math.sin(currentRotation + _rotSweep),
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = _colRot;
    canvas.drawCircle(arcEnd, _dotRadius, _paint);
  }

  void _paintMoveHandle(Canvas canvas, Offset center) {
    _paint
      ..style = PaintingStyle.fill
      ..color = _colMove.withValues(alpha: 0.9);
    canvas.drawCircle(center, _moveHandleRadius, _paint);

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF000000).withValues(alpha: 0.45);
    canvas.drawCircle(center, _moveHandleRadius, _paint);
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
  Camera camera,
) {
  final baseSize = _largestComponentSize(entity);
  final center = camera.worldToScreen(transform.position.toOffset());
  final halfW =
      (baseSize.width / 2) * camera.zoom * transform.scale.x.abs() + 2;
  final halfH =
      (baseSize.height / 2) * camera.zoom * transform.scale.y.abs() + 2;
  final corners = _buildRotatedCorners(
    center,
    halfW,
    halfH,
    transform.rotation,
  );

  return _ScreenBounds(
    center: center,
    halfW: halfW,
    halfH: halfH,
    rotation: transform.rotation,
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

  for (final component in entity.components) {
    consider(_sizeFromComponent(component));
  }

  return best;
}

Size? _sizeFromComponent(Component component) {
  // The extent on the definition first: the same answer the marquee and
  // the resize handles use. The branches below remain for anything that
  // has no definition at all.
  final extent = ComponentDefinitionRegistry.instance
      .definitionFor(component)
      ?.extent;
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
  if (component is UIComponent) {
    return component.size;
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
  static const double _arrowLength = GizmoConstants.arrowLength;
  static const double _arrowTipRadius = GizmoConstants.arrowTipRadius;
  static const double _rotRadius = GizmoConstants.rotRadius;
  static const double _rotDotRadius = GizmoConstants.rotDotRadius;
  static const double _scaleHandle = GizmoConstants.scaleHandle;
  static const double _rotSweep = GizmoConstants.rotSweep;
  static const double _axisSquareOffset = GizmoConstants.axisSquareOffset;
  static const double _axisSquareHitRadius = GizmoConstants.axisSquareHitRadius;
  static const double _moveHandleHitRadius = GizmoConstants.moveHandleHitRadius;

  /// Returns the [GizmoHitResult] for [screenPos].
  ///
  /// Tests handles on [selected] first, then falls back to body hit-test
  /// against all [entities] (last-added wins for overlaps).
  GizmoHitResult hitTest(
    Offset screenPos,
    Entity? selected,
    List<Entity> entities,
    Camera camera,
    Size canvasSize,
  ) {
    camera.viewportSize = canvasSize;

    if (selected != null && selected.isActive) {
      final result = _hitTestHandles(screenPos, selected, camera);
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

  GizmoHitResult _hitTestHandles(Offset pos, Entity entity, Camera camera) {
    final transform = entity.getComponent<TransformComponent>()!;
    final center = camera.worldToScreen(transform.position.toOffset());
    final bounds = _computeScreenBounds(entity, transform, camera);

    // Center free-move handle
    if ((pos - center).distance < _moveHandleHitRadius) {
      return GizmoHitResult(GizmoHandle.translateXY, entity);
    }

    // Scale corners
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

    // Rotation arc dot
    final rotSweepEnd = Offset(
      center.dx + _rotRadius * math.cos(transform.rotation + _rotSweep),
      center.dy + _rotRadius * math.sin(transform.rotation + _rotSweep),
    );
    if ((pos - rotSweepEnd).distance < _rotDotRadius) {
      return GizmoHitResult(GizmoHandle.rotate, entity);
    }

    // Translate X tip
    final xTip = center + const Offset(_arrowLength, 0);
    if ((pos - xTip).distance < _arrowTipRadius) {
      return GizmoHitResult(GizmoHandle.translateX, entity);
    }

    // Translate Y tip
    final yTip = center + const Offset(0, -_arrowLength);
    if ((pos - yTip).distance < _arrowTipRadius) {
      return GizmoHitResult(GizmoHandle.translateY, entity);
    }

    // Axis-scale squares (test after tips so arrowhead wins over shaft overlap)
    final xSquare = center + const Offset(_axisSquareOffset, 0);
    if ((pos - xSquare).distance < _axisSquareHitRadius) {
      return GizmoHitResult(GizmoHandle.scaleX, entity);
    }

    final ySquare = center + const Offset(0, -_axisSquareOffset);
    if ((pos - ySquare).distance < _axisSquareHitRadius) {
      return GizmoHitResult(GizmoHandle.scaleY, entity);
    }

    return const GizmoHitResult(GizmoHandle.none, null);
  }
}
