import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/scope/editor_scope.dart';
import '../core/view/editor_view.dart';

/// Something a module draws over the editor's viewport while authoring,
/// with the Level Designer open or not: a light's reach, a camera's
/// frustum, a trigger volume in space.
///
/// Unlike a designer overlay it needs no designer, so it is how a 3-D
/// module shows what it knows. It draws in screen space; [ViewportOverlayContext.project]
/// puts a point of the world on the screen in either kind of scene.
abstract class ViewportOverlay {
  /// Names it, and keys its visibility (`EditorScope.hiddenOverlays`).
  String get id;

  /// What a toggle for it says: `Light ranges`.
  String get label;

  /// Which scene modes it draws in.
  jge.Dimensions get dimensions => jge.Dimensions.both;

  /// Paint order among overlays: lower first (further back).
  int get order => 0;

  /// Draws it.
  void paint(ViewportOverlayContext context);
}

/// What a [ViewportOverlay] draws with, for one frame.
final class ViewportOverlayContext {
  /// The frame's drawing context.
  ViewportOverlayContext({
    required this.canvas,
    required this.size,
    required this.view,
    required this.scope,
    required bool Function(jge.Entity entity) isShown,
  }) : _isShown = isShown;

  /// Where to draw, in screen pixels.
  final Canvas canvas;

  /// The viewport's size.
  final Size size;

  /// How the world is seen.
  final EditorView view;

  /// The editor.
  final EditorScope scope;

  final bool Function(jge.Entity entity) _isShown;

  /// The world being edited.
  jge.World get world => scope.world;

  /// Whether [entity] is drawn in the viewport — not hidden by its eye or
  /// its layer. An overlay about an entity draws nothing for one that is
  /// not.
  bool isShown(jge.Entity entity) => _isShown(entity);

  /// Whether [entity] is part of the selection.
  bool isSelected(jge.Entity entity) =>
      scope.sceneState.selectedEntity.value?.id == entity.id ||
      scope.sceneState.isInMultiSelection(entity.id);

  /// Where [point] of the world is on the screen, or null when it is
  /// behind the viewer. In a 2-D scene its z is ignored.
  Offset? project(jge.Vector3 point) => view.isPlanar
      ? view.worldToScreen(Offset(point.x, point.y))
      : view.projectToScreen(point);
}
