import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../ui/overlay/gizmo_painter.dart';

/// Picks as 2-D does: each entity's turned box on screen, the last one
/// drawn on top; a marquee takes what lies within its area of the world.
class PlanarEntityPicker implements EntityPicker {
  PlanarEntityPicker([GizmoHitTester? hitTester])
    : hitTester = hitTester ?? GizmoHitTester();

  final GizmoHitTester hitTester;

  @override
  jge.Entity? pickAt(
    EditorView view,
    Offset screen,
    List<jge.Entity> candidates,
  ) => hitTester
      .hitTest(screen, null, candidates, view, view.viewportSize)
      .entity;

  @override
  List<jge.Entity> pickInRect(
    EditorView view,
    Rect screenRect,
    Iterable<jge.Entity> candidates,
  ) {
    // The screen rectangle's corners on the world plane; a turned view makes
    // a turned quad of them, so its bounds are what is searched.
    final corners = [
      view.screenToWorld(screenRect.topLeft),
      view.screenToWorld(screenRect.topRight),
      view.screenToWorld(screenRect.bottomLeft),
      view.screenToWorld(screenRect.bottomRight),
    ];
    final world = Rect.fromLTRB(
      corners.map((p) => p.dx).reduce(math.min),
      corners.map((p) => p.dy).reduce(math.min),
      corners.map((p) => p.dx).reduce(math.max),
      corners.map((p) => p.dy).reduce(math.max),
    );
    return DesignerGeometry.entitiesIn(
      world,
      candidates,
      pickable: (_) => true,
    );
  }
}
