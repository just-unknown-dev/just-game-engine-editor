import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// How the editor sees the scene: what it looks at, how close, and how to
/// get between the screen and the world.
///
/// Everything in the editor that draws over the viewport, picks, drags a
/// gizmo or pans goes through one of these rather than the engine's camera
/// itself. [GameCameraEditorView] is the 2-D view, on the engine's main
/// camera; `OrbitFlyEditorView` the 3-D one, orbiting a pivot. Tools that
/// speak rays ([screenToRay], [projectToScreen], [screenToGround]) work in
/// both.
///
/// The 2-D members are named as `jge.Camera`'s, so code written against the
/// camera reads the same against a view.
abstract interface class EditorView {
  /// The viewport's size in pixels.
  Size get viewportSize;
  set viewportSize(Size size);

  /// The world point at the centre of the view.
  Offset get position;
  set position(Offset value);

  /// The 3-D point the view centres on: where something new goes when no
  /// point is given. [position] at z = 0 in 2-D; the orbit's pivot in 3-D.
  jge.Vector3 get focus;

  /// Where a click at [screen] lands: on the world plane z = 0 in 2-D, on
  /// the ground (y = 0) in 3-D.
  jge.Vector3 screenToGround(Offset screen);

  /// Pixels per world unit at the centre of the view.
  double get zoom;

  /// The zoom range.
  double get minZoom;
  double get maxZoom;

  /// Whether the view looks straight at the world plane, as 2-D does.
  bool get isPlanar;

  /// The world point under [screen] — on the world plane z = 0.
  Offset screenToWorld(Offset screen);

  /// Where the world point [world] (at z = 0) is on screen.
  Offset worldToScreen(Offset world);

  /// The ray from the viewer through the pixel [screen] — what picking and
  /// gizmos in 3-D intersect with.
  jge.Ray3 screenToRay(Offset screen, [jge.Ray3? out]);

  /// Where the 3-D point [world] is on screen, or null when it is behind
  /// the viewer.
  Offset? projectToScreen(jge.Vector3 world);

  /// Draw through the view: world units on [canvas] from here on.
  void applyTransform(Canvas canvas, Size size);

  /// The world area in view.
  Rect get visibleWorldRect;

  /// Look at [world].
  void setPosition(Offset world);

  /// Set the zoom, within [minZoom]..[maxZoom].
  void setZoom(double zoom);

  /// Move the view by [delta] world units.
  void moveBy(Offset delta);

  /// Zoom to [zoom] keeping [worldPoint] where it is on screen.
  void zoomToPoint(Offset worldPoint, double zoom);

  /// The view as a value, to put back later.
  jge.CameraState get state;

  /// Show [state].
  void apply(jge.CameraState state);
}

/// The 2-D editor view: the engine's main camera, driven directly while the
/// editor authors (the brain is told not to).
class GameCameraEditorView implements EditorView {
  GameCameraEditorView(this._cameraOf);

  /// A view on a camera that never changes — a test's, say.
  GameCameraEditorView.of(jge.Camera camera) : _cameraOf = (() => camera);

  final jge.Camera Function() _cameraOf;

  /// The camera underneath.
  jge.Camera get camera => _cameraOf();

  @override
  Size get viewportSize => camera.viewportSize;
  @override
  set viewportSize(Size size) => camera.viewportSize = size;

  @override
  Offset get position => camera.position;
  @override
  set position(Offset value) => camera.position = value;

  @override
  jge.Vector3 get focus => jge.Vector3(camera.position.dx, camera.position.dy, 0);

  @override
  jge.Vector3 screenToGround(Offset screen) {
    final at = camera.screenToWorld(screen);
    return jge.Vector3(at.dx, at.dy, 0);
  }

  @override
  double get zoom => camera.zoom;
  @override
  double get minZoom => camera.minZoom;
  @override
  double get maxZoom => camera.maxZoom;

  @override
  bool get isPlanar => camera.isPlanar;

  @override
  Offset screenToWorld(Offset screen) => camera.screenToWorld(screen);

  @override
  Offset worldToScreen(Offset world) => camera.worldToScreen(world);

  @override
  jge.Ray3 screenToRay(Offset screen, [jge.Ray3? out]) =>
      camera.screenToWorldRay(screen, out);

  final jge.Vector3 _p = jge.Vector3.zero();

  @override
  Offset? projectToScreen(jge.Vector3 world) {
    camera.worldToScreen3(world, _p);
    // Depth outside 0..1 is before the near plane or past the far one.
    if (!camera.isPlanar && (_p.z < 0 || _p.z > 1)) return null;
    return Offset(_p.x, _p.y);
  }

  @override
  void applyTransform(Canvas canvas, Size size) =>
      camera.applyTransform(canvas, size);

  @override
  Rect get visibleWorldRect => camera.getVisibleBounds();

  @override
  void setPosition(Offset world) => camera.setPosition(world);

  @override
  void setZoom(double zoom) => camera.setZoom(zoom);

  @override
  void moveBy(Offset delta) => camera.moveBy(delta);

  @override
  void zoomToPoint(Offset worldPoint, double zoom) =>
      camera.zoomToPoint(worldPoint, zoom);

  @override
  jge.CameraState get state => camera.state;

  @override
  void apply(jge.CameraState state) => camera.apply(state);
}
