import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// The 3-D editor view: the engine's main camera, orbiting a [pivot].
///
/// [orbit] turns it around the pivot, [pan] slides the pivot across the
/// view, [dolly] moves in and out, [look] and [fly] turn and move it in
/// place (right mouse held, WASD), [focusOn] frames something, and
/// [viewFrom] snaps to an axis. Angles are the camera's: [pitch] below zero
/// looks down (the engine's +Y is down), [yaw] turns about the up axis with
/// 0 looking along +Z. Lengths are metres.
class OrbitFlyEditorView implements CameraSyncingView {
  /// A view on the camera [_cameraOf] returns, looking at the origin from
  /// a little above and in front.
  OrbitFlyEditorView(this._cameraOf);

  /// A view on a camera that never changes — a test's, say.
  OrbitFlyEditorView.of(jge.Camera camera) : _cameraOf = (() => camera);

  final jge.Camera Function() _cameraOf;

  /// The camera underneath.
  jge.Camera get camera => _cameraOf();

  /// The point it orbits.
  final jge.Vector3 pivot = jge.Vector3(0, -1, 0);

  /// Metres from the pivot to the camera.
  double distance = 10;

  /// Turn about the up axis, radians.
  double yaw = -0.6;

  /// Tilt, radians: below zero looks down.
  double pitch = -0.45;

  /// The closest [distance] may be.
  double minDistance = 0.1;

  /// The furthest [distance] may be.
  double maxDistance = 5000;

  /// Vertical field of view, radians.
  double fieldOfView = math.pi / 3;

  /// What it can see, near to far, metres.
  double near = 0.05, far = 5000;

  static const double _pitchLimit = math.pi / 2 - 0.01;

  /// Seen without perspective, as a plan or an elevation is drawn: things
  /// the same size near and far. Pad 5 switches.
  bool get orthographic => _orthographic;
  set orthographic(bool value) {
    if (value == _orthographic) return;
    _orthographic = value;
    // Back in perspective the lens ignores zoom; leave it as a flat view
    // would expect.
    if (!value) camera.zoom = 1;
    sync();
  }

  bool _orthographic = false;

  /// Where the view is and how it looks: what a bookmark keeps.
  ViewPose3D get pose => ViewPose3D(
    x: pivot.x,
    y: pivot.y,
    z: pivot.z,
    distance: distance,
    yaw: yaw,
    pitch: pitch,
    orthographic: _orthographic,
  );

  /// Goes back to [pose].
  set pose(ViewPose3D pose) {
    pivot.setValues(pose.x, pose.y, pose.z);
    distance = pose.distance;
    yaw = pose.yaw;
    pitch = pose.pitch;
    if (pose.orthographic != _orthographic) {
      orthographic = pose.orthographic;
    } else {
      sync();
    }
  }

  final jge.Quaternion _q = jge.Quaternion.identity();
  final jge.Vector3 _p = jge.Vector3.zero();

  /// The way the camera looks (unit length).
  jge.Vector3 get forward => jge.Vector3(
    math.cos(pitch) * math.sin(yaw),
    -math.sin(pitch),
    math.cos(pitch) * math.cos(yaw),
  );

  /// The camera's right, level with the ground.
  jge.Vector3 get right => jge.Vector3(math.cos(yaw), 0, -math.sin(yaw));

  /// The camera's own up (-Y when level).
  jge.Vector3 get up => right.cross(forward);

  /// Where the camera is.
  jge.Vector3 get eye {
    final f = forward;
    return jge.Vector3(
      pivot.x - f.x * distance,
      pivot.y - f.y * distance,
      pivot.z - f.z * distance,
    );
  }

  /// Puts the camera where the orbit says. Called after every change; call
  /// it yourself after setting [pivot], [distance], [yaw] or [pitch].
  @override
  void sync() {
    pitch = pitch.clamp(-_pitchLimit, _pitchLimit);
    distance = distance.clamp(minDistance, maxDistance);
    final at = eye;
    camera
      ..inSpace = true
      ..lens = _orthographic
          // As far behind as ahead: an elevation shows what is behind its
          // pivot too.
          ? jge.CameraLens.orthographic(near: -far, far: far)
          : jge.CameraLens.perspective(
              fieldOfView: fieldOfView,
              near: near,
              far: far,
            )
      ..pitch = pitch
      ..yaw = yaw
      ..rotation = 0
      ..position = Offset(at.x, at.y)
      ..z = at.z;
    // Orthographic: as many pixels a metre as perspective shows at the
    // pivot, so switching does not jump.
    if (_orthographic) camera.zoom = zoom;
  }

  /// Turns around the pivot by [screenDelta] pixels.
  void orbit(Offset screenDelta) {
    yaw += screenDelta.dx * 0.008;
    pitch -= screenDelta.dy * 0.008;
    sync();
  }

  /// Slides the pivot across the view, so what was under the pointer
  /// stays under it.
  void pan(Offset screenDelta) {
    final metresPerPixel =
        2 *
        distance *
        math.tan(fieldOfView / 2) /
        math.max(1, viewportSize.height);
    final r = right, u = up;
    pivot
      ..x += (-screenDelta.dx * r.x + screenDelta.dy * u.x) * metresPerPixel
      ..y += (-screenDelta.dx * r.y + screenDelta.dy * u.y) * metresPerPixel
      ..z += (-screenDelta.dx * r.z + screenDelta.dy * u.z) * metresPerPixel;
    sync();
  }

  /// Moves in ([amount] > 0) or out, by a share of the distance.
  void dolly(double amount) {
    distance *= math.exp(-amount);
    sync();
  }

  /// Turns in place (the pivot moves, the camera doesn't) by [screenDelta]
  /// pixels: right-mouse look.
  void look(Offset screenDelta) {
    final at = eye;
    yaw += screenDelta.dx * 0.004;
    pitch = (pitch - screenDelta.dy * 0.004).clamp(-_pitchLimit, _pitchLimit);
    final f = forward;
    pivot.setValues(
      at.x + f.x * distance,
      at.y + f.y * distance,
      at.z + f.z * distance,
    );
    sync();
  }

  /// Moves camera and pivot together, [move] metres along (right, up,
  /// forward).
  void fly(jge.Vector3 move) {
    final r = right, u = up, f = forward;
    pivot
      ..x += r.x * move.x + u.x * move.y + f.x * move.z
      ..y += r.y * move.x + u.y * move.y + f.y * move.z
      ..z += r.z * move.x + u.z * move.y + f.z * move.z;
    sync();
  }

  /// Frames [bounds]: the pivot at its centre, far enough back to see it
  /// whole.
  void focusOn(jge.Aabb3 bounds) {
    if (bounds.isEmpty) return;
    bounds.centerInto(pivot);
    final radius = math.max(0.25, bounds.min.distanceTo(bounds.max) / 2);
    distance = radius / math.sin(fieldOfView / 2) * 1.1;
    sync();
  }

  /// Looks along an axis: [pitch] and [yaw] in radians; the pivot stays.
  void viewFrom({required double yaw, required double pitch}) {
    this.yaw = yaw;
    this.pitch = pitch;
    sync();
  }

  @override
  Size get viewportSize => camera.viewportSize;
  @override
  set viewportSize(Size size) {
    if (size == camera.viewportSize) return;
    camera.viewportSize = size;
    // Orthographic, the zoom is worked out from the height: a view synced
    // before it had a size (a split pane, made at none) would otherwise
    // stay hundreds of times too far out.
    if (_orthographic) camera.zoom = zoom;
  }

  @override
  Offset get position => Offset(pivot.x, pivot.y);
  @override
  set position(Offset value) {
    pivot
      ..x = value.dx
      ..y = value.dy;
    sync();
  }

  @override
  jge.Vector3 get focus => jge.Vector3.copy(pivot);

  /// Pixels per metre at the pivot.
  @override
  double get zoom =>
      math.max(1, viewportSize.height) /
      (2 * distance * math.tan(fieldOfView / 2));

  @override
  double get minZoom =>
      math.max(1, viewportSize.height) /
      (2 * maxDistance * math.tan(fieldOfView / 2));

  @override
  double get maxZoom =>
      math.max(1, viewportSize.height) /
      (2 * minDistance * math.tan(fieldOfView / 2));

  @override
  bool get isPlanar => false;

  @override
  Offset screenToWorld(Offset screen) => camera.screenToWorld(screen);

  @override
  Offset worldToScreen(Offset world) => camera.worldToScreen(world);

  @override
  jge.Ray3 screenToRay(Offset screen, [jge.Ray3? out]) =>
      camera.screenToWorldRay(screen, out);

  /// Where [screen] meets the ground (y = 0, up is -Y); looking above the
  /// horizon, the point at the pivot's distance along the ray.
  @override
  jge.Vector3 screenToGround(Offset screen) {
    final ray = screenToRay(screen);
    final d = ray.direction;
    if (d.y.abs() > 1e-9) {
      final t = -ray.origin.y / d.y;
      if (t > 0) {
        return jge.Vector3(ray.origin.x + d.x * t, 0, ray.origin.z + d.z * t);
      }
    }
    final length = d.length;
    final t = length > 0 ? distance / length : 0.0;
    return jge.Vector3(
      ray.origin.x + d.x * t,
      ray.origin.y + d.y * t,
      ray.origin.z + d.z * t,
    );
  }

  @override
  Offset? projectToScreen(jge.Vector3 world) {
    camera.worldToScreen3(world, _p);
    if (_p.z < 0 || _p.z > 1) return null;
    return Offset(_p.x, _p.y);
  }

  @override
  void applyTransform(Canvas canvas, Size size) =>
      camera.applyTransform(canvas, size);

  @override
  Rect get visibleWorldRect => camera.getVisibleBounds();

  @override
  void setPosition(Offset world) => position = world;

  @override
  void setZoom(double zoom) {
    if (zoom <= 0) return;
    distance =
        math.max(1, viewportSize.height) /
        (2 * zoom * math.tan(fieldOfView / 2));
    sync();
  }

  @override
  void moveBy(Offset delta) {
    pivot
      ..x += delta.dx
      ..y += delta.dy;
    sync();
  }

  @override
  void zoomToPoint(Offset worldPoint, double zoom) => setZoom(zoom);

  @override
  jge.CameraState get state => camera.state;

  /// Shows [state]: its position and angles, the pivot [distance] ahead.
  @override
  void apply(jge.CameraState state) {
    yaw = state.yaw;
    pitch = state.pitch;
    final f = forward;
    pivot.setValues(
      state.position.dx + f.x * distance,
      state.position.dy + f.y * distance,
      state.z + f.z * distance,
    );
    sync();
  }

  /// The camera's rotation, for gizmos drawn in its frame.
  jge.Quaternion get rotation {
    camera.orientationInto(_q);
    return _q;
  }
}

/// Where an [OrbitFlyEditorView] is and how it looks: its pivot, how far
/// back, its turn and tilt, and whether it is orthographic. What a camera
/// bookmark in a 3-D scene keeps.
final class ViewPose3D {
  /// A pose.
  const ViewPose3D({
    required this.x,
    required this.y,
    required this.z,
    required this.distance,
    required this.yaw,
    required this.pitch,
    this.orthographic = false,
  });

  /// Restores one from [toJson]'s output.
  factory ViewPose3D.fromJson(Map<String, dynamic> json) {
    double n(String key) => (json[key] as num).toDouble();
    return ViewPose3D(
      x: n('x'),
      y: n('y'),
      z: n('z'),
      distance: n('distance'),
      yaw: n('yaw'),
      pitch: n('pitch'),
      orthographic: json['orthographic'] == true,
    );
  }

  /// The pivot.
  final double x, y, z;

  /// Metres back from the pivot.
  final double distance;

  /// Radians.
  final double yaw, pitch;

  /// Without perspective.
  final bool orthographic;

  /// For saving with the scene.
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'z': z,
    'distance': distance,
    'yaw': yaw,
    'pitch': pitch,
    if (orthographic) 'orthographic': true,
  };
}
