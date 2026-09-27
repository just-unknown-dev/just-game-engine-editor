import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../level_designer/overlays/designer_overlay.dart';
import '../level_designer/painters/designer_canvas.dart';
import '../level_designer/tools/tool_registry.dart';

/// Draws the level's camera rigs: what each virtual camera would show, and
/// the zones, bounds and tracks that steer them.
///
/// Every virtual camera gets its frame — bright for the live one, dashed for
/// the rest. The selected camera also shows how it frames its target: the
/// dead zone the target may roam, the soft zone it may not leave, and the
/// spot it is held to. Triggers and camera bounds are drawn for the whole
/// level, since they are level geometry as much as a platform is.
abstract final class CameraRigPainter {
  static const Color live = Color(0xFF40E0D0);
  static const Color standby = Color(0xFF7FA6A2);
  static const Color trigger = Color(0xFF7E57C2);
  static const Color bounds = Color(0xFFFFB74D);
  static const Color softZone = Color(0xFFFFD54F);
  static const Color track = Color(0xFF4FC3F7);

  static void paint(
    DesignerCanvas draw,
    jge.World world, {
    required bool Function(jge.Entity entity) isSelected,
    bool Function(jge.Entity entity)? isShown,
    jge.CameraBrain? brain,
    bool editingTrack = false,
  }) {
    // What the viewport hides — by the eye, or by the Level Designer
    // keeping to its map — takes its rig with it.
    bool drawn(jge.Entity entity) =>
        entity.isActive && (isShown == null || isShown(entity));
    _paintBounds(draw, world, drawn);
    _paintTriggers(draw, world, isSelected, drawn);
    for (final entity in world.query([
      jge.TransformComponent,
      jge.VirtualCameraComponent,
    ])) {
      if (!drawn(entity)) continue;
      _paintCamera(
        draw,
        world,
        entity,
        brain,
        isSelected(entity),
        editingTrack,
      );
    }
    for (final entity in world.query([
      jge.TransformComponent,
      jge.CameraTargetGroupComponent,
    ])) {
      if (drawn(entity) && isSelected(entity)) _paintGroup(draw, entity);
    }
  }

  static Offset _at(jge.Entity entity) =>
      entity.getComponent<jge.TransformComponent>()!.position.toOffset();

  /// What [entity]'s camera shows: from the brain when it has run, else from
  /// where the entity sits.
  static jge.CameraState stateOf(jge.Entity entity, jge.CameraBrain? brain) {
    final vcam = entity.getComponent<jge.VirtualCameraComponent>()!;
    return brain?.stateOf(entity) ??
        jge.CameraState(position: _at(entity), zoom: vcam.zoom);
  }

  /// The world rectangle a camera in [state] shows, for a view of [viewport].
  static Rect frameOf(jge.CameraState state, Size viewport) {
    final zoom = state.zoom <= 0 ? 1.0 : state.zoom;
    return Rect.fromCenter(
      center: state.position,
      width: viewport.width / zoom,
      height: viewport.height / zoom,
    );
  }

  static void _paintCamera(
    DesignerCanvas draw,
    jge.World world,
    jge.Entity entity,
    jge.CameraBrain? brain,
    bool selected,
    bool editingTrack,
  ) {
    final vcam = entity.getComponent<jge.VirtualCameraComponent>()!;
    final isLive = brain?.liveCamera?.id == entity.id;
    final isSolo = brain?.soloEntity == entity.id;
    final frame = frameOf(stateOf(entity, brain), draw.size);
    final name = entity.name ?? 'camera';

    if (isLive) {
      draw
        ..strokeWorldRect(frame, live.withValues(alpha: 0.95), strokeWidth: 2)
        ..label(
          draw.toScreenRect(frame).topLeft + const Offset(6, 4),
          '${isSolo ? 'SOLO' : 'LIVE'} · $name',
          live,
        );
    } else if (selected || vcam.enabled) {
      draw
        ..dashWorldRect(
          frame,
          standby.withValues(alpha: vcam.enabled ? 0.7 : 0.35),
        )
        ..label(
          draw.toScreenRect(frame).topLeft + const Offset(6, 4),
          vcam.enabled ? name : '$name (off)',
          standby.withValues(alpha: vcam.enabled ? 0.9 : 0.5),
        );
    }

    final dolly = entity.getComponent<jge.CameraDollyComponent>();
    if (dolly != null) _paintTrack(draw, dolly, selected && editingTrack);

    if (!selected) return;
    final framing = entity.getComponent<jge.CameraFramingComponent>();
    if (framing != null) _paintFraming(draw, frame, framing);
    final confiner = entity.getComponent<jge.CameraConfinerComponent>();
    if (confiner != null && confiner.boundsName.isNotEmpty) {
      final level = world.findEntityByName(confiner.boundsName);
      final area = level == null ? null : _boundsOf(level);
      if (area != null) {
        draw.strokeWorldRect(
          area,
          bounds.withValues(alpha: 0.9),
          strokeWidth: 2,
        );
      }
    }
  }

  static void _paintFraming(
    DesignerCanvas draw,
    Rect frame,
    jge.CameraFramingComponent framing,
  ) {
    // Where the target is held, and how far it may stray from there.
    final spot =
        frame.center +
        Offset(framing.screenX * frame.width, framing.screenY * frame.height);
    Rect zone(double w, double h) => Rect.fromCenter(
      center: spot,
      width: w * frame.width,
      height: h * frame.height,
    );
    draw
      ..dashWorldRect(
        zone(framing.softZoneWidth, framing.softZoneHeight),
        softZone.withValues(alpha: 0.75),
      )
      ..fillWorldRect(
        zone(framing.deadZoneWidth, framing.deadZoneHeight),
        live.withValues(alpha: 0.10),
      )
      ..strokeWorldRect(
        zone(framing.deadZoneWidth, framing.deadZoneHeight),
        live.withValues(alpha: 0.8),
      );
    final at = draw.toScreen(spot);
    final paint = Paint()
      ..color = live
      ..strokeWidth = 1.5;
    draw.canvas
      ..drawLine(at - const Offset(7, 0), at + const Offset(7, 0), paint)
      ..drawLine(at - const Offset(0, 7), at + const Offset(0, 7), paint);
  }

  static void _paintTrack(
    DesignerCanvas draw,
    jge.CameraDollyComponent dolly,
    bool handles,
  ) {
    final path = jge.DollyPath(dolly.waypoints, closed: dolly.closed);
    for (var i = 1; i < path.points.length; i++) {
      draw.worldLine(
        path.points[i - 1],
        path.points[i],
        track.withValues(alpha: 0.85),
        strokeWidth: 2,
      );
    }
    if (!handles) return;
    for (final point in dolly.waypoints) {
      draw.worldDot(point, track, radius: 6);
    }
  }

  static void _paintTriggers(
    DesignerCanvas draw,
    jge.World world,
    bool Function(jge.Entity) isSelected,
    bool Function(jge.Entity) drawn,
  ) {
    for (final entity in world.query([
      jge.TransformComponent,
      jge.CameraTriggerComponent,
    ])) {
      if (!drawn(entity)) continue;
      final zone = entity.getComponent<jge.CameraTriggerComponent>()!;
      final region = zone.regionAt(_at(entity));
      final strong = isSelected(entity) || zone.isInside;
      draw
        ..fillWorldRect(region, trigger.withValues(alpha: strong ? 0.18 : 0.10))
        ..strokeWorldRect(region, trigger.withValues(alpha: strong ? 1 : 0.8))
        ..label(
          draw.toScreenRect(region).topLeft + const Offset(6, 4),
          zone.cameraName.isEmpty
              ? 'camera zone'
              : 'camera trigger → ${zone.cameraName}',
          trigger,
        );
    }
  }

  static void _paintBounds(
    DesignerCanvas draw,
    jge.World world,
    bool Function(jge.Entity) drawn,
  ) {
    for (final entity in world.query([
      jge.TransformComponent,
      jge.CameraBoundsComponent,
    ])) {
      if (!drawn(entity)) continue;
      final area = _boundsOf(entity)!;
      draw
        ..dashWorldRect(area, bounds.withValues(alpha: 0.8))
        ..label(
          draw.toScreenRect(area).topLeft + const Offset(6, 4),
          'camera bounds',
          bounds,
        );
    }
  }

  static void _paintGroup(DesignerCanvas draw, jge.Entity entity) {
    final group = entity.getComponent<jge.CameraTargetGroupComponent>()!;
    if (group.resolved == 0) return;
    draw
      ..dashWorldRect(group.bounds, live.withValues(alpha: 0.6))
      ..worldDot(_at(entity), live, radius: 4);
  }

  static Rect? _boundsOf(jge.Entity entity) {
    final transform = entity.getComponent<jge.TransformComponent>();
    if (transform == null) return null;
    for (final component in entity.components) {
      if (component is jge.CameraBoundsSource) {
        return (component as jge.CameraBoundsSource).cameraBoundsAt(
          transform.position.toOffset(),
        );
      }
    }
    return null;
  }
}

/// [CameraRigPainter] as a Level Designer overlay, so it can be toggled like
/// the rulers and the minimap.
class CameraRigOverlay extends DesignerOverlay {
  CameraRigOverlay({required this.brain});

  /// The running game's camera brain, when there is one.
  final jge.CameraBrain? Function() brain;

  static const String overlayId = 'camera.rigs';

  @override
  String get id => overlayId;

  @override
  String get label => 'Cameras';

  @override
  IconData get icon => Icons.videocam_outlined;

  @override
  String? get description =>
      'Virtual camera frames, framing zones, triggers, bounds and tracks';

  @override
  int get order => OverlayOrder.region + 10;

  @override
  void paint(OverlayPaintContext context) => CameraRigPainter.paint(
    context.draw,
    context.world,
    brain: brain(),
    isSelected: context.isSelected,
    isShown: context.isShown,
    editingTrack: context.controller.toolId.value == BuiltInTools.dolly,
  );
}
